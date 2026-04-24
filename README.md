# Infrastructure Automation Scripts

A collection of PowerShell automation scripts for enterprise Windows and Azure environments. These scripts are used in production to monitor system health, automate routine tasks, and ensure infrastructure reliability.

## 📋 Overview

This repository contains automation tools I've developed while managing enterprise infrastructure for clients across banking, healthcare, and SaaS industries. Each script is designed to be:

- **Production-ready** - Error handling, logging, email notifications
- **Modular** - Easy to customize for different environments
- **Well-documented** - Clear comments and usage examples
- **Security-focused** - Credential management, audit logging

## 🚀 Scripts

### 1. AD-HealthCheck.ps1
**Purpose:** Comprehensive Active Directory health monitoring  
**Features:**
- Checks domain controller replication status
- Validates FSMO role holders
- Tests DNS resolution and zone health
- Monitors SYSVOL/NETLOGON replication
- Sends email alerts on failures

**Use Case:** Daily automated monitoring for multi-site AD environments

```powershell
.\AD-HealthCheck.ps1 -Domain "contoso.local" -EmailTo "admin@company.com"
```

---

### 2. Backup-Monitor.ps1
**Purpose:** Monitor Veeam backup job status and alert on failures  
**Features:**
- Queries Veeam Backup & Replication job history
- Identifies failed, warning, or missing backups
- Generates detailed HTML report
- Sends email alerts to administrators
- Logs all checks for audit trail

**Use Case:** Nightly backup verification for disaster recovery compliance

```powershell
.\Backup-Monitor.ps1 -VeeamServer "backup01" -EmailTo "backup-team@company.com"
```

---

### 3. Azure-ResourceInventory.ps1
**Purpose:** Generate comprehensive Azure resource inventory with cost analysis  
**Features:**
- Lists all resources across subscriptions
- Calculates current month costs per resource
- Identifies unused or underutilized resources
- Exports to CSV for further analysis
- Tracks resource tags and compliance

**Use Case:** Monthly cost optimization and resource governance

```powershell
.\Azure-ResourceInventory.ps1 -SubscriptionId "xxxx-xxxx-xxxx-xxxx"
```

---

### 4. Certificate-ExpiryMonitor.ps1
**Purpose:** Monitor SSL/TLS certificate expiration dates  
**Features:**
- Scans IIS bindings for certificates
- Checks Exchange certificate expiration
- Monitors domain controller certificates
- Sends alerts 30/15/7 days before expiry
- Generates compliance report

**Use Case:** Prevent certificate-related outages in production

```powershell
.\Certificate-ExpiryMonitor.ps1 -AlertThresholdDays 30
```

---

### 5. User-ProvisioningTemplate.ps1
**Purpose:** Standardized Active Directory user account creation  
**Features:**
- Creates user with proper OU placement
- Assigns security groups based on department
- Sets Exchange mailbox attributes
- Configures home drive and profile path
- Sends welcome email with credentials

**Use Case:** HR onboarding automation with consistent security policies

```powershell
.\User-ProvisioningTemplate.ps1 -FirstName "John" -LastName "Doe" -Department "IT"
```

---

## 🛠️ Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Active Directory PowerShell Module (for AD scripts)
- Azure PowerShell Module (for Azure scripts)
- Veeam PowerShell Snap-in (for backup scripts)
- Appropriate administrative permissions

## 📦 Installation

1. Clone this repository:
```powershell
git clone https://github.com/Naveen032506/Infrastructure-Automation.git
cd Infrastructure-Automation
```

2. Review and customize parameters in each script
3. Configure email settings in the configuration section
4. Test in non-production environment first

## ⚙️ Configuration

Each script has a configuration section at the top. Key settings:

```powershell
# Email Configuration
$SmtpServer = "smtp.company.com"
$EmailFrom = "automation@company.com"
$EmailTo = "admin@company.com"

# Logging
$LogPath = "C:\Logs\Automation"
```

## 🔒 Security Considerations

- Store credentials using `Get-Credential` and Windows Credential Manager
- Run scripts with least-privilege service accounts
- Enable PowerShell script logging for audit trails
- Review execution policies and code signing requirements
- Sanitize any sensitive data before logging

## 📊 Real-World Usage

These scripts are actively used in production environments:

- **Revalize LLC (SaaS):** Daily AD health checks, nightly backup monitoring, monthly Azure cost reports
- **Enterprise Banking Client:** Certificate monitoring across 50+ servers
- **Healthcare Provider:** Automated user provisioning for 1,000+ staff

## 🤝 Contributing

This repository represents production automation from real enterprise environments. If you have suggestions or improvements:

1. Fork the repository
2. Create a feature branch
3. Submit a pull request with clear description

## 📄 License

MIT License - Feel free to use and modify for your own infrastructure automation needs.

## 👤 Author

**Naveen** - Senior IT Consultant  
- 10+ years managing enterprise infrastructure
- Specialist in Azure, Active Directory, PowerShell automation
- Top Rated Plus on Upwork with 100% Job Success Score

## 📞 Support

For questions about these scripts or custom automation needs:
- Email: naveenprashanth52@gmail.com
- LinkedIn: https://www.linkedin.com/in/naveen-prashanth-496b0a79/

---

*Last updated: April 2026*
