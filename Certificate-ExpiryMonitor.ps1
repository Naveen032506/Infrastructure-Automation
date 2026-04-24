<#
.SYNOPSIS
    SSL/TLS certificate expiration monitoring script

.DESCRIPTION
    Scans servers for certificates nearing expiration and sends alerts

.PARAMETER AlertThresholdDays
    Number of days before expiration to trigger alert (default: 30)

.PARAMETER EmailTo
    Email address for alerts

.EXAMPLE
    .\Certificate-ExpiryMonitor.ps1 -AlertThresholdDays 30 -EmailTo "admin@company.com"

.NOTES
    Author: Naveen
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [int]$AlertThresholdDays = 30,
    
    [Parameter(Mandatory=$false)]
    [string]$EmailTo,
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "C:\Logs\CertMonitor"
)

# Configuration
$SmtpServer = "smtp.company.com"
$EmailFrom = "cert-monitoring@company.com"

# Create log directory
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

$LogFile = Join-Path $LogPath "CertMonitor_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

Write-Log "Starting Certificate Expiry Monitor"
Write-Log "Alert Threshold: $AlertThresholdDays days"

# Initialize results
$AllCertificates = @()
$ExpiringCerts = @()

# Check 1: Local Computer Certificate Store
Write-Log "Checking local computer certificate store..."
try {
    $LocalCerts = Get-ChildItem -Path Cert:\LocalMachine\My
    
    foreach ($Cert in $LocalCerts) {
        $DaysUntilExpiry = ($Cert.NotAfter - (Get-Date)).Days
        
        $CertInfo = [PSCustomObject]@{
            Source = "Local Machine"
            Subject = $Cert.Subject
            Issuer = $Cert.Issuer
            Thumbprint = $Cert.Thumbprint
            NotBefore = $Cert.NotAfter
            NotAfter = $Cert.NotAfter
            DaysUntilExpiry = $DaysUntilExpiry
            Status = if ($DaysUntilExpiry -lt 0) { "EXPIRED" } 
                     elseif ($DaysUntilExpiry -le $AlertThresholdDays) { "EXPIRING SOON" } 
                     else { "OK" }
        }
        
        $AllCertificates += $CertInfo
        
        if ($DaysUntilExpiry -le $AlertThresholdDays) {
            Write-Log "Certificate expiring in $DaysUntilExpiry days: $($Cert.Subject)" -Level "WARN"
            $ExpiringCerts += $CertInfo
        }
    }
    
    Write-Log "Found $($LocalCerts.Count) certificates in local machine store"
} catch {
    Write-Log "Error checking local certificates: $($_.Exception.Message)" -Level "ERROR"
}

# Check 2: IIS Bindings (if IIS is installed)
if (Get-Module -ListAvailable -Name WebAdministration) {
    Write-Log "Checking IIS certificate bindings..."
    try {
        Import-Module WebAdministration -ErrorAction Stop
        
        $IISBindings = Get-ChildItem -Path IIS:\SslBindings
        
        foreach ($Binding in $IISBindings) {
            if ($Binding.Thumbprint) {
                $Cert = Get-ChildItem -Path "Cert:\LocalMachine\My\$($Binding.Thumbprint)" -ErrorAction SilentlyContinue
                
                if ($Cert) {
                    $DaysUntilExpiry = ($Cert.NotAfter - (Get-Date)).Days
                    
                    if ($DaysUntilExpiry -le $AlertThresholdDays) {
                        Write-Log "IIS binding certificate expiring in $DaysUntilExpiry days: $($Binding.Host)" -Level "WARN"
                    }
                }
            }
        }
        
        Write-Log "Checked $($IISBindings.Count) IIS bindings"
    } catch {
        Write-Log "Error checking IIS bindings: $($_.Exception.Message)" -Level "WARN"
    }
}

# Check 3: Remote Desktop Certificate
Write-Log "Checking Remote Desktop certificate..."
try {
    $RDPCertThumbprint = (Get-WmiObject -Class "Win32_TSGeneralSetting" -Namespace root\cimv2\terminalservices -Filter "TerminalName='RDP-Tcp'").SSLCertificateSHA1Hash
    
    if ($RDPCertThumbprint) {
        $RDPCert = Get-ChildItem -Path "Cert:\LocalMachine\My\$RDPCertThumbprint" -ErrorAction SilentlyContinue
        
        if ($RDPCert) {
            $DaysUntilExpiry = ($RDPCert.NotAfter - (Get-Date)).Days
            
            if ($DaysUntilExpiry -le $AlertThresholdDays) {
                Write-Log "RDP certificate expiring in $DaysUntilExpiry days" -Level "WARN"
            }
        }
    }
} catch {
    Write-Log "Could not check RDP certificate: $($_.Exception.Message)" -Level "WARN"
}

# Generate summary
Write-Log "========================================="
Write-Log "Certificate Monitoring Summary"
Write-Log "Total Certificates: $($AllCertificates.Count)"
Write-Log "Expiring Soon: $($ExpiringCerts.Count)"
Write-Log "========================================="

# Generate HTML report
if ($ExpiringCerts.Count -gt 0 -or $AllCertificates.Count -gt 0) {
    $HtmlReport = @"
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; }
        h2 { color: #333; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; font-size: 12px; }
        th { background-color: #4CAF50; color: white; }
        .expired { background-color: #f44336; color: white; }
        .expiring { background-color: #ff9800; color: white; }
        .ok { background-color: #4CAF50; color: white; }
        .summary { background-color: #f0f0f0; padding: 15px; margin: 20px 0; }
    </style>
</head>
<body>
    <h2>Certificate Expiration Monitor Report</h2>
    
    <div class="summary">
        <strong>Report Date:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")<br>
        <strong>Alert Threshold:</strong> $AlertThresholdDays days<br>
        <strong>Total Certificates:</strong> $($AllCertificates.Count)<br>
        <strong>Certificates Expiring Soon:</strong> $($ExpiringCerts.Count)
    </div>
"@
    
    if ($ExpiringCerts.Count -gt 0) {
        $HtmlReport += "<h3>⚠️ Certificates Requiring Attention</h3><table>"
        $HtmlReport += "<tr><th>Source</th><th>Subject</th><th>Expires</th><th>Days Until Expiry</th><th>Status</th></tr>"
        
        foreach ($Cert in $ExpiringCerts | Sort-Object DaysUntilExpiry) {
            $StatusClass = if ($Cert.Status -eq "EXPIRED") { "expired" } else { "expiring" }
            $HtmlReport += "<tr class='$StatusClass'>"
            $HtmlReport += "<td>$($Cert.Source)</td>"
            $HtmlReport += "<td>$($Cert.Subject)</td>"
            $HtmlReport += "<td>$($Cert.NotAfter)</td>"
            $HtmlReport += "<td><strong>$($Cert.DaysUntilExpiry)</strong></td>"
            $HtmlReport += "<td>$($Cert.Status)</td>"
            $HtmlReport += "</tr>"
        }
        $HtmlReport += "</table>"
    }
    
    $HtmlReport += "<h3>All Certificates</h3><table>"
    $HtmlReport += "<tr><th>Source</th><th>Subject</th><th>Expires</th><th>Days Until Expiry</th><th>Status</th></tr>"
    
    foreach ($Cert in $AllCertificates | Sort-Object DaysUntilExpiry) {
        $StatusClass = switch ($Cert.Status) {
            "EXPIRED" { "expired" }
            "EXPIRING SOON" { "expiring" }
            default { "ok" }
        }
        $HtmlReport += "<tr class='$StatusClass'>"
        $HtmlReport += "<td>$($Cert.Source)</td>"
        $HtmlReport += "<td>$($Cert.Subject)</td>"
        $HtmlReport += "<td>$($Cert.NotAfter)</td>"
        $HtmlReport += "<td>$($Cert.DaysUntilExpiry)</td>"
        $HtmlReport += "<td>$($Cert.Status)</td>"
        $HtmlReport += "</tr>"
    }
    
    $HtmlReport += "</table></body></html>"
    
    # Send email if configured and certificates expiring
    if ($EmailTo -and $ExpiringCerts.Count -gt 0) {
        try {
            $Subject = "⚠️ Certificate Alert - $($ExpiringCerts.Count) Certificates Expiring Soon"
            
            Send-MailMessage `
                -SmtpServer $SmtpServer `
                -From $EmailFrom `
                -To $EmailTo `
                -Subject $Subject `
                -Body $HtmlReport `
                -BodyAsHtml `
                -Priority High
            
            Write-Log "Email alert sent to $EmailTo"
        } catch {
            Write-Log "Failed to send email: $($_.Exception.Message)" -Level "ERROR"
        }
    }
}

Write-Log "Certificate monitoring complete"
Write-Log "Log file: $LogFile"

# Exit with error if certificates expiring
if ($ExpiringCerts.Count -gt 0) {
    exit 1
} else {
    exit 0
}
