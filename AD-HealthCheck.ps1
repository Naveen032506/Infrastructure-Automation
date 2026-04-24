<#
.SYNOPSIS
    Active Directory health monitoring script

.DESCRIPTION
    Performs comprehensive health checks on Active Directory domain controllers including:
    - Replication status
    - FSMO role verification
    - DNS health
    - SYSVOL/NETLOGON shares
    - Services status
    
.PARAMETER Domain
    The AD domain to check (e.g., "contoso.local")

.PARAMETER EmailTo
    Email address to send alerts

.EXAMPLE
    .\AD-HealthCheck.ps1 -Domain "corp.local" -EmailTo "admin@corp.com"

.NOTES
    Author: Naveen
    Version: 1.2
    Last Updated: April 2026
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Domain,
    
    [Parameter(Mandatory=$false)]
    [string]$EmailTo,
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "C:\Logs\ADHealthCheck"
)

# Configuration
$SmtpServer = "smtp.company.com"
$EmailFrom = "ad-monitoring@company.com"
$AlertOnError = $true

# Create log directory if it doesn't exist
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

$LogFile = Join-Path $LogPath "ADHealthCheck_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $LogMessage
    
    switch ($Level) {
        "ERROR" { Write-Host $LogMessage -ForegroundColor Red }
        "WARN"  { Write-Host $LogMessage -ForegroundColor Yellow }
        default { Write-Host $LogMessage -ForegroundColor White }
    }
}

# Initialize results
$Results = @()
$ErrorCount = 0

Write-Log "Starting Active Directory Health Check for domain: $Domain"

# Import Active Directory module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log "Active Directory module loaded successfully"
} catch {
    Write-Log "Failed to load Active Directory module: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

# Get all domain controllers
try {
    $DomainControllers = Get-ADDomainController -Filter * -Server $Domain
    Write-Log "Found $($DomainControllers.Count) domain controllers"
} catch {
    Write-Log "Failed to retrieve domain controllers: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

# Check 1: Domain Controller Replication Status
Write-Log "Checking AD replication status..."
foreach ($DC in $DomainControllers) {
    try {
        $ReplStatus = Get-ADReplicationPartnerMetadata -Target $DC.HostName -Scope Domain
        
        foreach ($Partner in $ReplStatus) {
            $LastRepl = $Partner.LastReplicationSuccess
            $TimeSinceRepl = (Get-Date) - $LastRepl
            
            if ($TimeSinceRepl.TotalHours -gt 24) {
                Write-Log "WARNING: DC $($DC.HostName) last replicated with $($Partner.Partner) $([math]::Round($TimeSinceRepl.TotalHours,2)) hours ago" -Level "WARN"
                $Results += [PSCustomObject]@{
                    Check = "Replication"
                    Server = $DC.HostName
                    Status = "WARNING"
                    Details = "Last replication: $([math]::Round($TimeSinceRepl.TotalHours,2)) hours ago"
                }
                $ErrorCount++
            } else {
                Write-Log "OK: DC $($DC.HostName) replication with $($Partner.Partner) is healthy"
                $Results += [PSCustomObject]@{
                    Check = "Replication"
                    Server = $DC.HostName
                    Status = "OK"
                    Details = "Last replication: $([math]::Round($TimeSinceRepl.TotalHours,2)) hours ago"
                }
            }
        }
    } catch {
        Write-Log "ERROR checking replication on $($DC.HostName): $($_.Exception.Message)" -Level "ERROR"
        $ErrorCount++
    }
}

# Check 2: FSMO Roles
Write-Log "Verifying FSMO role holders..."
try {
    $Forest = Get-ADForest -Server $Domain
    $DomainInfo = Get-ADDomain -Server $Domain
    
    $FSMORoles = @{
        "Schema Master" = $Forest.SchemaMaster
        "Domain Naming Master" = $Forest.DomainNamingMaster
        "PDC Emulator" = $DomainInfo.PDCEmulator
        "RID Master" = $DomainInfo.RIDMaster
        "Infrastructure Master" = $DomainInfo.InfrastructureMaster
    }
    
    foreach ($Role in $FSMORoles.GetEnumerator()) {
        Write-Log "OK: $($Role.Key) is held by $($Role.Value)"
        $Results += [PSCustomObject]@{
            Check = "FSMO Roles"
            Server = $Role.Value
            Status = "OK"
            Details = $Role.Key
        }
    }
} catch {
    Write-Log "ERROR verifying FSMO roles: $($_.Exception.Message)" -Level "ERROR"
    $ErrorCount++
}

# Check 3: DNS Health
Write-Log "Checking DNS resolution..."
foreach ($DC in $DomainControllers) {
    try {
        $DNSResult = Resolve-DnsName -Name $DC.HostName -Server $DC.IPv4Address -ErrorAction Stop
        Write-Log "OK: DNS resolution successful for $($DC.HostName)"
        $Results += [PSCustomObject]@{
            Check = "DNS"
            Server = $DC.HostName
            Status = "OK"
            Details = "Resolved to $($DNSResult.IPAddress -join ', ')"
        }
    } catch {
        Write-Log "ERROR: DNS resolution failed for $($DC.HostName)" -Level "ERROR"
        $Results += [PSCustomObject]@{
            Check = "DNS"
            Server = $DC.HostName
            Status = "ERROR"
            Details = "DNS resolution failed"
        }
        $ErrorCount++
    }
}

# Check 4: SYSVOL and NETLOGON shares
Write-Log "Checking SYSVOL and NETLOGON shares..."
foreach ($DC in $DomainControllers) {
    $SysvolPath = "\\$($DC.HostName)\SYSVOL"
    $NetlogonPath = "\\$($DC.HostName)\NETLOGON"
    
    # Check SYSVOL
    if (Test-Path $SysvolPath) {
        Write-Log "OK: SYSVOL share accessible on $($DC.HostName)"
        $Results += [PSCustomObject]@{
            Check = "SYSVOL"
            Server = $DC.HostName
            Status = "OK"
            Details = "Share accessible"
        }
    } else {
        Write-Log "ERROR: SYSVOL share NOT accessible on $($DC.HostName)" -Level "ERROR"
        $Results += [PSCustomObject]@{
            Check = "SYSVOL"
            Server = $DC.HostName
            Status = "ERROR"
            Details = "Share not accessible"
        }
        $ErrorCount++
    }
    
    # Check NETLOGON
    if (Test-Path $NetlogonPath) {
        Write-Log "OK: NETLOGON share accessible on $($DC.HostName)"
        $Results += [PSCustomObject]@{
            Check = "NETLOGON"
            Server = $DC.HostName
            Status = "OK"
            Details = "Share accessible"
        }
    } else {
        Write-Log "ERROR: NETLOGON share NOT accessible on $($DC.HostName)" -Level "ERROR"
        $Results += [PSCustomObject]@{
            Check = "NETLOGON"
            Server = $DC.HostName
            Status = "ERROR"
            Details = "Share not accessible"
        }
        $ErrorCount++
    }
}

# Check 5: Critical Services
Write-Log "Checking critical AD services..."
$CriticalServices = @("NTDS", "DNS", "Netlogon", "W32Time", "DFS Replication")

foreach ($DC in $DomainControllers) {
    foreach ($ServiceName in $CriticalServices) {
        try {
            $Service = Get-Service -ComputerName $DC.HostName -Name $ServiceName -ErrorAction Stop
            
            if ($Service.Status -ne "Running") {
                Write-Log "WARNING: Service '$ServiceName' is $($Service.Status) on $($DC.HostName)" -Level "WARN"
                $Results += [PSCustomObject]@{
                    Check = "Services"
                    Server = $DC.HostName
                    Status = "WARNING"
                    Details = "$ServiceName is $($Service.Status)"
                }
                $ErrorCount++
            } else {
                Write-Log "OK: Service '$ServiceName' is running on $($DC.HostName)"
                $Results += [PSCustomObject]@{
                    Check = "Services"
                    Server = $DC.HostName
                    Status = "OK"
                    Details = "$ServiceName is running"
                }
            }
        } catch {
            Write-Log "ERROR checking service '$ServiceName' on $($DC.HostName): $($_.Exception.Message)" -Level "ERROR"
            $ErrorCount++
        }
    }
}

# Generate summary
Write-Log "========================================="
Write-Log "AD Health Check Complete"
Write-Log "Total Checks: $($Results.Count)"
Write-Log "Errors/Warnings: $ErrorCount"
Write-Log "========================================="

# Send email if configured and errors found
if ($EmailTo -and ($ErrorCount -gt 0 -or -not $AlertOnError)) {
    try {
        $Body = @"
<html>
<head>
    <style>
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
        .error { background-color: #f44336; color: white; }
        .warning { background-color: #ff9800; color: white; }
        .ok { background-color: #4CAF50; color: white; }
    </style>
</head>
<body>
    <h2>Active Directory Health Check Report - $Domain</h2>
    <p><strong>Date:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    <p><strong>Total Issues:</strong> $ErrorCount</p>
    
    <table>
        <tr>
            <th>Check</th>
            <th>Server</th>
            <th>Status</th>
            <th>Details</th>
        </tr>
"@
        foreach ($Result in $Results) {
            $StatusClass = switch ($Result.Status) {
                "OK" { "ok" }
                "WARNING" { "warning" }
                "ERROR" { "error" }
            }
            $Body += "<tr><td>$($Result.Check)</td><td>$($Result.Server)</td><td class='$StatusClass'>$($Result.Status)</td><td>$($Result.Details)</td></tr>"
        }
        
        $Body += "</table></body></html>"
        
        $Subject = "AD Health Check - $Domain - $ErrorCount Issues Found"
        
        Send-MailMessage -SmtpServer $SmtpServer -From $EmailFrom -To $EmailTo -Subject $Subject -Body $Body -BodyAsHtml
        Write-Log "Email report sent to $EmailTo"
    } catch {
        Write-Log "Failed to send email: $($_.Exception.Message)" -Level "ERROR"
    }
}

Write-Log "Log file saved to: $LogFile"
exit $ErrorCount
