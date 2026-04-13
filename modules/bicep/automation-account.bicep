// automation-account.bicep
// Deploys Azure Automation Account with system-assigned managed identity,
// linked Log Analytics workspace, runbook stubs, schedules, and Graph
// role assignments for the managed identity.

targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Name of the Automation Account')
param automationAccountName string = 'aa-automation-hub'

@description('Resource ID of the Log Analytics workspace to link')
param logAnalyticsWorkspaceId string

@description('Enable daily compliance report schedule')
param enableComplianceSchedule bool = true

@description('Enable weekly license report schedule')
param enableLicenseReportSchedule bool = true

@description('Tags to apply to all resources')
param tags object = {}

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var complianceScheduleName = 'schedule-daily-compliance'
var licenseReportScheduleName = 'schedule-weekly-license-report'

// ---------------------------------------------------------------------------
// Automation Account
// ---------------------------------------------------------------------------

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
    publicNetworkAccess: true
    disableLocalAuth: false
    encryption: {
      keySource: 'Microsoft.Automation'
    }
  }
}

// ---------------------------------------------------------------------------
// Linked Log Analytics workspace
// ---------------------------------------------------------------------------

resource linkedWorkspace 'Microsoft.OperationalInsights/workspaces/linkedServices@2020-08-01' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${last(split(logAnalyticsWorkspaceId, '/'))}/Automation'
  properties: {
    resourceId: automationAccount.id
  }
}

// ---------------------------------------------------------------------------
// Runbook definitions (imported as stubs -- upload actual .ps1 content
// via CI/CD or the Azure portal after deployment)
// ---------------------------------------------------------------------------

resource runbookRemoveUser 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'Remove-AzureADUser'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Offboard a user: disable, revoke sessions, remove groups/licenses, convert mailbox'
    logProgress: true
    logVerbose: false
  }
}

resource runbookBulkLicense 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'Set-BulkLicenseAssignment'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Assign or swap licenses in bulk from CSV or group membership'
    logProgress: true
    logVerbose: false
  }
}

resource runbookCompliance 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'Get-NonCompliantDevices'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Report non-compliant and inactive Intune devices'
    logProgress: true
    logVerbose: false
  }
}

resource runbookRemediation 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'Invoke-IntuneRemediation'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Trigger Intune sync on non-compliant devices'
    logProgress: true
    logVerbose: false
  }
}

resource runbookSecurityReport 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'Get-AzureSecurityReport'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Security posture report: secure score, PIM, CA policies, MFA status'
    logProgress: true
    logVerbose: false
  }
}

resource runbookLicenseReport 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'Get-M365LicenseReport'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'M365 license utilisation report with capacity warnings'
    logProgress: true
    logVerbose: false
  }
}

// ---------------------------------------------------------------------------
// Schedules
// ---------------------------------------------------------------------------

resource complianceSchedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = if (enableComplianceSchedule) {
  parent: automationAccount
  name: complianceScheduleName
  properties: {
    description: 'Run compliance report daily at 06:00 UTC'
    startTime: '2025-01-01T06:00:00+00:00'
    frequency: 'Day'
    interval: 1
    timeZone: 'UTC'
  }
}

resource licenseReportSchedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = if (enableLicenseReportSchedule) {
  parent: automationAccount
  name: licenseReportScheduleName
  properties: {
    description: 'Run license report weekly on Monday at 07:00 UTC'
    startTime: '2025-01-06T07:00:00+00:00'
    frequency: 'Week'
    interval: 1
    timeZone: 'UTC'
  }
}

// ---------------------------------------------------------------------------
// Role Assignments for Managed Identity
//
// Note: Graph API permissions (User.ReadWrite.All, Group.ReadWrite.All, etc.)
// must be granted separately via PowerShell/CLI after deployment:
//
//   $sp = Get-MgServicePrincipal -Filter "appId eq '<managed-identity-app-id>'"
//   $graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
//   New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id `
//       -PrincipalId $sp.Id -ResourceId $graphSp.Id -AppRoleId '<role-id>'
//
// The Reader role below is for Azure resource enumeration.
// ---------------------------------------------------------------------------

resource readerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(automationAccount.id, 'Reader', subscription().subscriptionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output automationAccountId string = automationAccount.id
output managedIdentityPrincipalId string = automationAccount.identity.principalId
