<#
.SYNOPSIS
    Azure resource inventory and cost analysis script

.DESCRIPTION
    Generates comprehensive inventory of Azure resources with cost analysis,
    identifies unused resources, and exports data for governance.

.PARAMETER SubscriptionId
    Azure subscription ID to inventory

.PARAMETER ExportPath
    Path to save CSV export (default: C:\Reports\Azure)

.EXAMPLE
    .\Azure-ResourceInventory.ps1 -SubscriptionId "xxxx-xxxx-xxxx-xxxx"

.NOTES
    Author: Naveen
    Version: 1.0
    Requires: Az PowerShell module
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [string]$ExportPath = "C:\Reports\Azure",
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "C:\Logs\AzureInventory"
)

# Create directories
foreach ($Path in @($ExportPath, $LogPath)) {
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

$LogFile = Join-Path $LogPath "AzureInventory_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$CsvFile = Join-Path $ExportPath "AzureResources_$(Get-Date -Format 'yyyyMMdd').csv"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $LogMessage
    Write-Host $LogMessage
}

Write-Log "Starting Azure Resource Inventory"

# Check if Az module is installed
try {
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        throw "Az PowerShell module not installed. Run: Install-Module -Name Az -AllowClobber"
    }
    Import-Module Az.Accounts -ErrorAction Stop
    Write-Log "Az module loaded successfully"
} catch {
    Write-Log "Failed to load Az module: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

# Connect to Azure (uses cached credentials if available)
try {
    $Context = Get-AzContext
    if (-not $Context) {
        Write-Log "No Azure context found. Initiating login..."
        Connect-AzAccount -ErrorAction Stop | Out-Null
        $Context = Get-AzContext
    }
    Write-Log "Connected to Azure as: $($Context.Account.Id)"
} catch {
    Write-Log "Failed to connect to Azure: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

# Set subscription if specified
if ($SubscriptionId) {
    try {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        Write-Log "Using subscription: $SubscriptionId"
    } catch {
        Write-Log "Failed to set subscription: $($_.Exception.Message)" -Level "ERROR"
        exit 1
    }
} else {
    $SubscriptionId = $Context.Subscription.Id
    Write-Log "Using current subscription: $SubscriptionId"
}

# Get subscription details
$Subscription = Get-AzSubscription -SubscriptionId $SubscriptionId
Write-Log "Subscription Name: $($Subscription.Name)"

# Initialize results array
$AllResources = @()

# Get all resources
Write-Log "Retrieving all resources..."
try {
    $Resources = Get-AzResource
    Write-Log "Found $($Resources.Count) resources"
} catch {
    Write-Log "Failed to retrieve resources: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

# Process each resource
$Counter = 0
foreach ($Resource in $Resources) {
    $Counter++
    Write-Progress -Activity "Processing Resources" -Status "$Counter of $($Resources.Count)" -PercentComplete (($Counter / $Resources.Count) * 100)
    
    Write-Log "Processing: $($Resource.Name) ($($Resource.ResourceType))"
    
    # Get resource tags
    $Tags = if ($Resource.Tags) {
        ($Resource.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
    } else {
        "No tags"
    }
    
    # Determine resource status (varies by type)
    $Status = "Running"
    $AdditionalInfo = ""
    
    # Check specific resource types for more details
    switch -Wildcard ($Resource.ResourceType) {
        "Microsoft.Compute/virtualMachines" {
            try {
                $VM = Get-AzVM -ResourceGroupName $Resource.ResourceGroupName -Name $Resource.Name -Status
                $PowerState = ($VM.Statuses | Where-Object { $_.Code -like "PowerState/*" }).DisplayStatus
                $Status = $PowerState
                $AdditionalInfo = "Size: $($VM.HardwareProfile.VmSize)"
            } catch {
                Write-Log "Could not get VM status for $($Resource.Name)" -Level "WARN"
            }
        }
        "Microsoft.Storage/storageAccounts" {
            try {
                $Storage = Get-AzStorageAccount -ResourceGroupName $Resource.ResourceGroupName -Name $Resource.Name
                $AdditionalInfo = "SKU: $($Storage.Sku.Name), Kind: $($Storage.Kind)"
            } catch {
                Write-Log "Could not get storage details for $($Resource.Name)" -Level "WARN"
            }
        }
        "Microsoft.Sql/servers" {
            $AdditionalInfo = "SQL Server"
        }
        "Microsoft.Web/sites" {
            try {
                $WebApp = Get-AzWebApp -ResourceGroupName $Resource.ResourceGroupName -Name $Resource.Name
                $AdditionalInfo = "Plan: $($WebApp.AppServicePlan), State: $($WebApp.State)"
                $Status = $WebApp.State
            } catch {
                Write-Log "Could not get web app details for $($Resource.Name)" -Level "WARN"
            }
        }
    }
    
    # Create resource object
    $ResourceObj = [PSCustomObject]@{
        SubscriptionName = $Subscription.Name
        SubscriptionId = $SubscriptionId
        ResourceGroup = $Resource.ResourceGroupName
        ResourceName = $Resource.Name
        ResourceType = $Resource.ResourceType
        Location = $Resource.Location
        Status = $Status
        Tags = $Tags
        AdditionalInfo = $AdditionalInfo
        ResourceId = $Resource.ResourceId
        CreatedTime = "N/A"  # Azure doesn't expose creation time easily
    }
    
    $AllResources += $ResourceObj
}

Write-Progress -Activity "Processing Resources" -Completed

# Generate statistics
Write-Log "========================================="
Write-Log "Inventory Summary"
Write-Log "Total Resources: $($AllResources.Count)"

$ResourcesByType = $AllResources | Group-Object ResourceType | Sort-Object Count -Descending
Write-Log "`nTop Resource Types:"
foreach ($Type in $ResourcesByType | Select-Object -First 10) {
    Write-Log "  $($Type.Name): $($Type.Count)"
}

$ResourcesByLocation = $AllResources | Group-Object Location | Sort-Object Count -Descending
Write-Log "`nResources by Location:"
foreach ($Location in $ResourcesByLocation) {
    Write-Log "  $($Location.Name): $($Location.Count)"
}

$ResourcesByRG = $AllResources | Group-Object ResourceGroup | Sort-Object Count -Descending
Write-Log "`nTop Resource Groups:"
foreach ($RG in $ResourcesByRG | Select-Object -First 5) {
    Write-Log "  $($RG.Name): $($RG.Count)"
}

# Identify resources without tags
$UntaggedResources = $AllResources | Where-Object { $_.Tags -eq "No tags" }
if ($UntaggedResources) {
    Write-Log "`nWARNING: $($UntaggedResources.Count) resources have no tags" -Level "WARN"
}

# Identify stopped VMs
$StoppedVMs = $AllResources | Where-Object { $_.ResourceType -eq "Microsoft.Compute/virtualMachines" -and $_.Status -like "*deallocated*" }
if ($StoppedVMs) {
    Write-Log "`nInfo: $($StoppedVMs.Count) VMs are deallocated (potential cost savings)"
}

Write-Log "========================================="

# Export to CSV
try {
    $AllResources | Export-Csv -Path $CsvFile -NoTypeInformation -Force
    Write-Log "Resource inventory exported to: $CsvFile"
} catch {
    Write-Log "Failed to export CSV: $($_.Exception.Message)" -Level "ERROR"
}

# Generate HTML report
$HtmlReport = @"
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; }
        h2 { color: #333; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; font-size: 12px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
        .summary { background-color: #f0f0f0; padding: 15px; margin: 20px 0; }
        .warning { background-color: #fff3cd; padding: 10px; margin: 10px 0; }
    </style>
</head>
<body>
    <h2>Azure Resource Inventory Report</h2>
    <div class="summary">
        <strong>Subscription:</strong> $($Subscription.Name)<br>
        <strong>Date:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")<br>
        <strong>Total Resources:</strong> $($AllResources.Count)<br>
        <strong>Untagged Resources:</strong> $($UntaggedResources.Count)
    </div>
"@

if ($StoppedVMs.Count -gt 0) {
    $HtmlReport += "<div class='warning'><strong>⚠️ $($StoppedVMs.Count) VMs are currently deallocated</strong></div>"
}

$HtmlReport += "<h3>Resource Breakdown by Type</h3><table><tr><th>Resource Type</th><th>Count</th></tr>"
foreach ($Type in $ResourcesByType | Select-Object -First 15) {
    $HtmlReport += "<tr><td>$($Type.Name)</td><td>$($Type.Count)</td></tr>"
}
$HtmlReport += "</table></body></html>"

$HtmlFile = Join-Path $ExportPath "AzureInventory_$(Get-Date -Format 'yyyyMMdd').html"
$HtmlReport | Out-File -FilePath $HtmlFile -Force
Write-Log "HTML report saved to: $HtmlFile"

Write-Log "Azure Resource Inventory Complete"
Write-Log "Log file: $LogFile"

exit 0
