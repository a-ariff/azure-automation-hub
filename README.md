Azure Automation Hub

[Azure] [PowerShell] [Microsoft Graph] [CI] [License: MIT]

Production-ready PowerShell runbooks for Azure Automation. Covers user lifecycle management, Intune device compliance, security posture reporting, and license utilisation – built for MSP and enterprise environments using Microsoft Graph exclusively (no deprecated AzureAD module).

Table of Contents

- Architecture
- What is in this repo
- Runbook reference
- Authentication
- Setup
- Schedule recommendations
- Dependencies
- Contributing

Architecture

    Azure Automation Account (Managed Identity)
      |
      +-- Microsoft Graph API
      |     |
      |     +-- Entra ID (users, groups, roles, PIM)
      |     +-- Intune (devices, compliance, sync)
      |     +-- Exchange Online (mailbox conversion)
      |     +-- Security (secure score, CA policies)
      |     +-- Reports (MFA registration, licenses)
      |
      +-- Log Analytics Workspace
      |     |
      |     +-- Runbook logs and diagnostics
      |
      +-- Schedules
            |
            +-- Daily: compliance reports
            +-- Weekly: license utilisation
            +-- On-demand: user offboarding, remediation

What is in this repo

    azure-automation-hub/
      runbooks/
        user-management/
          New-AzureADUser.ps1               -- create user with groups and license
          Remove-AzureADUser.ps1            -- full offboarding workflow
          Set-BulkLicenseAssignment.ps1     -- bulk license assign/swap from CSV or group
        device-compliance/
          Get-NonCompliantDevices.ps1       -- compliance and inactivity report
          Invoke-IntuneRemediation.ps1      -- force sync on non-compliant devices
        reporting/
          Get-AzureSecurityReport.ps1       -- secure score, PIM, CA, MFA report
          Get-M365LicenseReport.ps1         -- license utilisation with capacity alerts
      modules/
        bicep/
          automation-account.bicep          -- deploy the full automation infrastructure
      .github/
        workflows/
          lint.yml                          -- PSScriptAnalyzer + Bicep validation

Runbook reference

  -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  Runbook                         Purpose                                                                                     Key Graph permissions
  ------------------------------- ------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------
  New-AzureADUser.ps1             Provision a new user with group and license assignment                                      User.ReadWrite.All, Group.ReadWrite.All

  Remove-AzureADUser.ps1          Disable account, revoke sessions, remove groups/licenses, convert mailbox, notify manager   User.ReadWrite.All, Group.ReadWrite.All, Mail.Send, Directory.ReadWrite.All

  Set-BulkLicenseAssignment.ps1   Assign or swap licenses in bulk from CSV or Entra group                                     User.ReadWrite.All, Group.Read.All, Directory.Read.All

  Get-NonCompliantDevices.ps1     Report on non-compliant and inactive Intune devices                                         DeviceManagementManagedDevices.Read.All

  Invoke-IntuneRemediation.ps1    Trigger device sync for non-compliant devices                                               DeviceManagementManagedDevices.ReadWrite.All

  Get-AzureSecurityReport.ps1     Security posture: secure score, PIM, Conditional Access, MFA                                SecurityEvents.Read.All, Policy.Read.All, RoleManagement.Read.Directory, Reports.Read.All

  Get-M365LicenseReport.ps1       License utilisation with 90%+ capacity warnings                                             Directory.Read.All, Organization.Read.All
  -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

Authentication

Managed Identity (recommended): All runbooks connect with Connect-MgGraph -Identity. The Automation Account’s system-assigned managed identity needs the Graph permissions listed above.

Service Principal (alternative): For local testing or environments without managed identity support, use Connect-MgGraph -ClientId ... -TenantId ... -CertificateThumbprint ....

Grant Graph API permissions to the managed identity after deployment:

    # get the managed identity service principal
    $mi = Get-MgServicePrincipal -Filter "displayName eq 'aa-automation-hub'"

    # get the Graph service principal
    $graph = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

    # assign User.ReadWrite.All (example)
    $role = $graph.AppRoles | Where-Object { $_.Value -eq 'User.ReadWrite.All' }
    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $mi.Id `
        -PrincipalId $mi.Id `
        -ResourceId $graph.Id `
        -AppRoleId $role.Id

Setup

1.  Deploy the infrastructure using the Bicep module:

    az deployment group create \
        --resource-group rg-automation \
        --template-file modules/bicep/automation-account.bicep \
        --parameters automationAccountName='aa-automation-hub' \
                     logAnalyticsWorkspaceId='/subscriptions/.../workspaces/law-001'

2.  Grant Graph permissions to the managed identity (see Authentication section above).

3.  Import runbooks – either through the Azure Portal or via CI/CD. The Bicep module creates runbook resource stubs; upload the actual .ps1 content:

    az automation runbook replace-content \
        --resource-group rg-automation \
        --automation-account-name aa-automation-hub \
        --name Remove-AzureADUser \
        --content @runbooks/user-management/Remove-AzureADUser.ps1

4.  Link schedules to runbooks and configure Automation variables (TenantId, NotificationEmail, AutomationMailbox).

Schedule recommendations

  ----------------------------------------------------------------------------------------------
  Runbook                     Frequency                    Notes
  --------------------------- ---------------------------- -------------------------------------
  Get-NonCompliantDevices     Daily 06:00 UTC              Catches overnight drift

  Get-M365LicenseReport       Weekly Monday 07:00 UTC      License reconciliation

  Get-AzureSecurityReport     Weekly Friday 08:00 UTC      End-of-week security review

  Invoke-IntuneRemediation    Daily 12:00 UTC              Post-compliance-report sync

  Remove-AzureADUser          On-demand                    Triggered by ITSM or HR workflow

  Set-BulkLicenseAssignment   On-demand                    Triggered by licence true-up events
  ----------------------------------------------------------------------------------------------

Dependencies

  -------------------------------------------------------------------------------------------------------------------------
  Module                                         Version                  Purpose
  ---------------------------------------------- ------------------------ -------------------------------------------------
  Microsoft.Graph.Users                          >= 2.0.0                 User CRUD, license management

  Microsoft.Graph.Groups                         >= 2.0.0                 Group membership operations

  Microsoft.Graph.Identity.DirectoryManagement   >= 2.0.0                 SKU and role queries

  Microsoft.Graph.Identity.SignIns               >= 2.0.0                 Conditional Access, MFA reports

  Microsoft.Graph.Identity.Governance            >= 2.0.0                 PIM role assignments

  Microsoft.Graph.Security                       >= 2.0.0                 Secure score

  Microsoft.Graph.DeviceManagement               >= 2.0.0                 Intune device queries and actions

  Microsoft.Graph.Users.Actions                  >= 2.0.0                 Revoke sessions, send mail

  Az.Accounts                                    >= 2.12.0                Azure authentication (used by Bicep deployment)

  ExchangeOnlineManagement                       >= 3.2.0                 Mailbox conversion (optional, offboarding only)

  PSScriptAnalyzer                               >= 1.21.0                CI linting (dev dependency only)
  -------------------------------------------------------------------------------------------------------------------------

Contributing

1.  Fork the repository
2.  Create a feature branch
3.  Run PSScriptAnalyzer locally: Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning
4.  Open a pull request – the lint workflow validates automatically

License

MIT – see LICENSE for details.

Back to top
