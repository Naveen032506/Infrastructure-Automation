<#
.SYNOPSIS
    Active Directory user provisioning automation script

.DESCRIPTION
    Creates new AD user accounts with standardized configuration including:
    - Proper OU placement based on department
    - Security group assignments
    - Home drive creation
    - Email notification
    
.PARAMETER FirstName
    User's first name

.PARAMETER LastName
    User's last name

.PARAMETER Department
    Department (IT, HR, Finance, Sales, etc.)

.PARAMETER Title
    Job title

.PARAMETER Manager
    Manager's username (optional)

.EXAMPLE
    .\User-ProvisioningTemplate.ps1 -FirstName "John" -LastName "Doe" -Department "IT" -Title "System Administrator"

.NOTES
    Author: Naveen
    Version: 1.0
    Requires: Active Directory PowerShell Module
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$FirstName,
    
    [Parameter(Mandatory=$true)]
    [string]$LastName,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("IT", "HR", "Finance", "Sales", "Marketing", "Operations")]
    [string]$Department,
    
    [Parameter(Mandatory=$false)]
    [string]$Title,
    
    [Parameter(Mandatory=$false)]
    [string]$Manager,
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "C:\Logs\UserProvisioning"
)

# Configuration - Update these for your environment
$DomainName = "corp.local"
$CompanyName = "Contoso Ltd"
$EmailDomain = "contoso.com"
$DefaultPassword = "Welcome@2026!" # Should be changed on first login
$HomeDriveServer = "\\fileserver\users$"

# Department-specific settings
$DepartmentConfig = @{
    "IT" = @{
        OU = "OU=IT,OU=Users,DC=corp,DC=local"
        Groups = @("IT-Staff", "VPN-Users", "Remote-Desktop-Users")
        Description = "IT Department"
    }
    "HR" = @{
        OU = "OU=HR,OU=Users,DC=corp,DC=local"
        Groups = @("HR-Staff", "VPN-Users")
        Description = "Human Resources"
    }
    "Finance" = @{
        OU = "OU=Finance,OU=Users,DC=corp,DC=local"
        Groups = @("Finance-Staff", "VPN-Users")
        Description = "Finance Department"
    }
    "Sales" = @{
        OU = "OU=Sales,OU=Users,DC=corp,DC=local"
        Groups = @("Sales-Staff", "VPN-Users", "CRM-Users")
        Description = "Sales Department"
    }
    "Marketing" = @{
        OU = "OU=Marketing,OU=Users,DC=corp,DC=local"
        Groups = @("Marketing-Staff", "VPN-Users")
        Description = "Marketing Department"
    }
    "Operations" = @{
        OU = "OU=Operations,OU=Users,DC=corp,DC=local"
        Groups = @("Operations-Staff", "VPN-Users")
        Description = "Operations Department"
    }
}

# Create log directory
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

$LogFile = Join-Path $LogPath "UserProvisioning_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $LogMessage
    
    switch ($Level) {
        "ERROR" { Write-Host $LogMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $LogMessage -ForegroundColor Green }
        "WARN" { Write-Host $LogMessage -ForegroundColor Yellow }
        default { Write-Host $LogMessage -ForegroundColor White }
    }
}

Write-Log "==========================================="
Write-Log "Starting User Provisioning"
Write-Log "User: $FirstName $LastName"
Write-Log "Department: $Department"
Write-Log "==========================================="

# Load Active Directory module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log "Active Directory module loaded"
} catch {
    Write-Log "Failed to load Active Directory module: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

# Generate username (first initial + last name)
$Username = "$($FirstName.Substring(0,1))$LastName".ToLower()
$Email = "$Username@$EmailDomain"
$DisplayName = "$FirstName $LastName"

Write-Log "Generated username: $Username"
Write-Log "Email address: $Email"

# Check if user already exists
try {
    $ExistingUser = Get-ADUser -Filter "SamAccountName -eq '$Username'" -ErrorAction SilentlyContinue
    
    if ($ExistingUser) {
        Write-Log "ERROR: User $Username already exists!" -Level "ERROR"
        exit 1
    }
} catch {
    Write-Log "Error checking for existing user: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

# Get department configuration
$Config = $DepartmentConfig[$Department]
$TargetOU = $Config.OU

# Create secure password
$SecurePassword = ConvertTo-SecureString -String $DefaultPassword -AsPlainText -Force

# Create user parameters
$UserParams = @{
    SamAccountName = $Username
    UserPrincipalName = $Email
    Name = $DisplayName
    GivenName = $FirstName
    Surname = $LastName
    DisplayName = $DisplayName
    EmailAddress = $Email
    Department = $Department
    Company = $CompanyName
    Path = $TargetOU
    AccountPassword = $SecurePassword
    Enabled = $true
    ChangePasswordAtLogon = $true
    PasswordNeverExpires = $false
}

# Add title if provided
if ($Title) {
    $UserParams.Add("Title", $Title)
    Write-Log "Job title: $Title"
}

# Add manager if provided
if ($Manager) {
    try {
        $ManagerObj = Get-ADUser -Identity $Manager -ErrorAction Stop
        $UserParams.Add("Manager", $ManagerObj.DistinguishedName)
        Write-Log "Manager: $Manager"
    } catch {
        Write-Log "WARNING: Could not find manager: $Manager" -Level "WARN"
    }
}

# Create the user
Write-Log "Creating user account in $TargetOU..."
try {
    New-ADUser @UserParams -ErrorAction Stop
    Write-Log "User account created successfully" -Level "SUCCESS"
} catch {
    Write-Log "Failed to create user: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

# Wait for replication
Start-Sleep -Seconds 5

# Add user to groups
Write-Log "Adding user to security groups..."
foreach ($Group in $Config.Groups) {
    try {
        Add-ADGroupMember -Identity $Group -Members $Username -ErrorAction Stop
        Write-Log "Added to group: $Group" -Level "SUCCESS"
    } catch {
        Write-Log "Failed to add to group $Group : $($_.Exception.Message)" -Level "WARN"
    }
}

# Create home directory
$HomePath = Join-Path $HomeDriveServer $Username
Write-Log "Creating home directory: $HomePath"

try {
    if (-not (Test-Path $HomePath)) {
        New-Item -ItemType Directory -Path $HomePath -Force | Out-Null
        
        # Set permissions (user gets full control)
        $Acl = Get-Acl $HomePath
        $Permission = "$DomainName\$Username", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
        $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $Permission
        $Acl.SetAccessRule($AccessRule)
        Set-Acl -Path $HomePath -AclObject $Acl
        
        Write-Log "Home directory created and permissions set" -Level "SUCCESS"
        
        # Set home directory in AD
        Set-ADUser -Identity $Username -HomeDrive "H:" -HomeDirectory $HomePath
    }
} catch {
    Write-Log "Failed to create home directory: $($_.Exception.Message)" -Level "WARN"
}

# Generate welcome email (HTML)
$EmailBody = @"
<html>
<body style="font-family: Arial, sans-serif;">
    <h2>Welcome to $CompanyName!</h2>
    
    <p>Dear $FirstName,</p>
    
    <p>Your user account has been created. Below are your login details:</p>
    
    <table border="1" cellpadding="10" style="border-collapse: collapse;">
        <tr>
            <td><strong>Username</strong></td>
            <td>$Username</td>
        </tr>
        <tr>
            <td><strong>Email</strong></td>
            <td>$Email</td>
        </tr>
        <tr>
            <td><strong>Temporary Password</strong></td>
            <td>$DefaultPassword</td>
        </tr>
        <tr>
            <td><strong>Department</strong></td>
            <td>$Department</td>
        </tr>
    </table>
    
    <p><strong>Important:</strong> You will be required to change your password on first login.</p>
    
    <h3>Next Steps:</h3>
    <ul>
        <li>Log in to your computer using the credentials above</li>
        <li>Check your email at $Email</li>
        <li>Contact IT Support if you need any assistance</li>
    </ul>
    
    <p>Best regards,<br>IT Support Team</p>
</body>
</html>
"@

# Save email body to file (email sending would require SMTP configuration)
$EmailFile = Join-Path $LogPath "WelcomeEmail_$Username.html"
$EmailBody | Out-File -FilePath $EmailFile -Force
Write-Log "Welcome email saved to: $EmailFile"

# Generate provisioning summary
Write-Log "==========================================="
Write-Log "USER PROVISIONING COMPLETE"
Write-Log "Username: $Username"
Write-Log "Email: $Email"
Write-Log "OU: $TargetOU"
Write-Log "Groups: $($Config.Groups -join ', ')"
Write-Log "Home Directory: $HomePath"
Write-Log "==========================================="
Write-Log "IMPORTANT: Share these credentials with the user:"
Write-Log "  Username: $Username"
Write-Log "  Password: $DefaultPassword (must change on first login)"
Write-Log "==========================================="

# Return user object
$NewUser = Get-ADUser -Identity $Username -Properties *

Write-Output "
╔══════════════════════════════════════════════════════════╗
║           USER PROVISIONING SUCCESSFUL                    ║
╚══════════════════════════════════════════════════════════╝

User Details:
  Name: $DisplayName
  Username: $Username
  Email: $Email
  Department: $Department
  OU: $TargetOU
  
Groups Assigned:
  $($Config.Groups -join "`n  ")
  
Next Steps:
  1. Share credentials with user
  2. Verify email delivery
  3. Test login access
  
Log File: $LogFile
"

exit 0
