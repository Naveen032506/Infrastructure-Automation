<#
.SYNOPSIS
    Veeam Backup job monitoring and alerting script

.DESCRIPTION
    Monitors Veeam Backup & Replication job status, identifies failures,
    and sends email alerts with detailed HTML reports.

.PARAMETER VeeamServer
    Veeam Backup & Replication server hostname

.PARAMETER EmailTo
    Email address for alerts

.PARAMETER HoursToCheck
    Number of hours to look back for job history (default: 24)

.EXAMPLE
    .\Backup-Monitor.ps1 -VeeamServer "BACKUP01" -EmailTo "backup-team@company.com"

.NOTES
    Author: Naveen
    Version: 1.1
    Requires: Veeam PowerShell Snap-in
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$VeeamServer,
    
    [Parameter(Mandatory=$true)]
    [string]$EmailTo,
    
    [Parameter(Mandatory=$false)]
    [int]$HoursToCheck = 24,
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "C:\Logs\BackupMonitor"
)

# Configuration
$SmtpServer = "smtp.company.com"
$EmailFrom = "backup-monitoring@company.com"

# Create log directory
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

$LogFile = Join-Path $LogPath "BackupMonitor_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $LogMessage
    Write-Host $LogMessage
}

Write-Log "Starting Veeam Backup Monitor"
Write-Log "Veeam Server: $VeeamServer"
Write-Log "Checking last $HoursToCheck hours"

# Load Veeam PowerShell Snap-in
try {
    if (-not (Get-PSSnapin -Name VeeamPSSnapin -ErrorAction SilentlyContinue)) {
        Add-PSSnapin VeeamPSSnapin -ErrorAction Stop
        Write-Log "Veeam PowerShell Snap-in loaded successfully"
    }
} catch {
    Write-Log "Failed to load Veeam PowerShell Snap-in: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

# Connect to Veeam server
try {
    Connect-VBRServer -Server $VeeamServer -ErrorAction Stop
    Write-Log "Connected to Veeam server: $VeeamServer"
} catch {
    Write-Log "Failed to connect to Veeam server: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

# Get backup jobs
try {
    $BackupJobs = Get-VBRJob | Where-Object { $_.JobType -eq "Backup" }
    Write-Log "Found $($BackupJobs.Count) backup jobs"
} catch {
    Write-Log "Failed to retrieve backup jobs: $($_.Exception.Message)" -Level "ERROR"
    Disconnect-VBRServer
    exit 1
}

# Initialize results
$Results = @()
$FailedJobs = 0
$WarningJobs = 0
$SuccessJobs = 0
$MissingJobs = 0

# Calculate time range
$StartTime = (Get-Date).AddHours(-$HoursToCheck)

# Check each job
foreach ($Job in $BackupJobs) {
    Write-Log "Checking job: $($Job.Name)"
    
    try {
        # Get last session for this job
        $Session = Get-VBRBackupSession | 
            Where-Object { $_.JobName -eq $Job.Name -and $_.EndTime -ge $StartTime } | 
            Sort-Object EndTime -Descending | 
            Select-Object -First 1
        
        if ($Session) {
            $Duration = $Session.EndTime - $Session.CreationTime
            $DurationMinutes = [math]::Round($Duration.TotalMinutes, 0)
            
            # Determine status
            $Status = switch ($Session.Result) {
                "Success" { 
                    $SuccessJobs++
                    "SUCCESS"
                }
                "Warning" { 
                    $WarningJobs++
                    "WARNING"
                }
                "Failed" { 
                    $FailedJobs++
                    "FAILED"
                }
                default { 
                    $WarningJobs++
                    "UNKNOWN"
                }
            }
            
            Write-Log "$($Job.Name): $Status - Duration: $DurationMinutes mins" -Level $(if ($Status -eq "FAILED") { "ERROR" } elseif ($Status -eq "WARNING") { "WARN" } else { "INFO" })
            
            $Results += [PSCustomObject]@{
                JobName = $Job.Name
                Status = $Status
                StartTime = $Session.CreationTime
                EndTime = $Session.EndTime
                Duration = "$DurationMinutes minutes"
                DataSize = [math]::Round($Session.BackupStats.DataSize / 1GB, 2)
                TransferredData = [math]::Round($Session.BackupStats.BackupSize / 1GB, 2)
                Message = $Session.Result
            }
        } else {
            # No session found in time range
            Write-Log "$($Job.Name): NO BACKUP RUN in last $HoursToCheck hours" -Level "ERROR"
            $MissingJobs++
            
            $Results += [PSCustomObject]@{
                JobName = $Job.Name
                Status = "MISSING"
                StartTime = "N/A"
                EndTime = "N/A"
                Duration = "N/A"
                DataSize = 0
                TransferredData = 0
                Message = "No backup run in last $HoursToCheck hours"
            }
        }
    } catch {
        Write-Log "Error checking job $($Job.Name): $($_.Exception.Message)" -Level "ERROR"
        $FailedJobs++
    }
}

# Disconnect from Veeam
Disconnect-VBRServer

# Generate summary
Write-Log "========================================="
Write-Log "Backup Monitoring Summary"
Write-Log "Total Jobs: $($BackupJobs.Count)"
Write-Log "Successful: $SuccessJobs"
Write-Log "Warnings: $WarningJobs"
Write-Log "Failed: $FailedJobs"
Write-Log "Missing: $MissingJobs"
Write-Log "========================================="

# Generate HTML report
$HtmlReport = @"
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; }
        h2 { color: #333; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
        .success { background-color: #d4edda; }
        .warning { background-color: #fff3cd; }
        .failed { background-color: #f8d7da; }
        .missing { background-color: #f8d7da; }
        .summary { 
            background-color: #f0f0f0; 
            padding: 15px; 
            border-radius: 5px; 
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <h2>Veeam Backup Monitoring Report</h2>
    
    <div class="summary">
        <strong>Report Date:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")<br>
        <strong>Veeam Server:</strong> $VeeamServer<br>
        <strong>Time Range:</strong> Last $HoursToCheck hours<br><br>
        <strong>Total Jobs:</strong> $($BackupJobs.Count)<br>
        <strong>Successful:</strong> $SuccessJobs<br>
        <strong>Warnings:</strong> $WarningJobs<br>
        <strong>Failed:</strong> $FailedJobs<br>
        <strong>Missing:</strong> $MissingJobs
    </div>
    
    <table>
        <tr>
            <th>Job Name</th>
            <th>Status</th>
            <th>Start Time</th>
            <th>End Time</th>
            <th>Duration</th>
            <th>Data Size (GB)</th>
            <th>Transferred (GB)</th>
            <th>Message</th>
        </tr>
"@

foreach ($Result in $Results) {
    $RowClass = switch ($Result.Status) {
        "SUCCESS" { "success" }
        "WARNING" { "warning" }
        "FAILED" { "failed" }
        "MISSING" { "missing" }
    }
    
    $HtmlReport += @"
        <tr class="$RowClass">
            <td>$($Result.JobName)</td>
            <td><strong>$($Result.Status)</strong></td>
            <td>$($Result.StartTime)</td>
            <td>$($Result.EndTime)</td>
            <td>$($Result.Duration)</td>
            <td>$($Result.DataSize)</td>
            <td>$($Result.TransferredData)</td>
            <td>$($Result.Message)</td>
        </tr>
"@
}

$HtmlReport += "</table></body></html>"

# Send email
try {
    $TotalIssues = $FailedJobs + $WarningJobs + $MissingJobs
    
    if ($TotalIssues -gt 0) {
        $Subject = "⚠️ Veeam Backup Alert - $TotalIssues Issues Found"
        $Priority = "High"
    } else {
        $Subject = "✅ Veeam Backup Report - All Jobs Successful"
        $Priority = "Normal"
    }
    
    Send-MailMessage `
        -SmtpServer $SmtpServer `
        -From $EmailFrom `
        -To $EmailTo `
        -Subject $Subject `
        -Body $HtmlReport `
        -BodyAsHtml `
        -Priority $Priority
    
    Write-Log "Email report sent to $EmailTo"
} catch {
    Write-Log "Failed to send email: $($_.Exception.Message)" -Level "ERROR"
}

Write-Log "Log file saved to: $LogFile"

# Exit with error code if issues found
if ($FailedJobs -gt 0 -or $MissingJobs -gt 0) {
    exit 1
} else {
    exit 0
}
