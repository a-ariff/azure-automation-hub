<#
.SYNOPSIS
    Offboards an Azure AD (Entra ID) user account with comprehensive cleanup.

.DESCRIPTION
    This Azure Automation runbook disables a user account, revokes sessions,
    backs up and removes group memberships, removes license assignments,
    converts the mailbox to shared (if requested), sets an out-of-office reply,
    and notifies the user's manager. Uses Microsoft.Graph exclusively (not the
    deprecated AzureAD module).

.PARAMETER UserPrincipalName
    The UPN of the user to offboard.

.PARAMETER RevokeSessions
    Revoke all active sign-in sessions immediately.

.PARAMETER ConvertToSharedMailbox
    Convert the user's mailbox to a shared mailbox. Requires the Exchange Online
    Management module or Exchange Online REST calls.

.PARAMETER RemoveLicenses
    Remove all license assignments from the user.

.PARAMETER BackupGroupMemberships
    Save group membership list to an Automation variable before removal.

.PARAMETER ManagerNotification
    Send an email notification to the user's manager.

.EXAMPLE
    Remove-AzureADUser.ps1 -UserPrincipalName "jsmith@contoso.com" -RevokeSessions $true -RemoveLicenses $true

.NOTES
    Author:  Ariff Mohamed
    Version: 1.0
    Requires: Microsoft.Graph.Users, Microsoft.Graph.Groups,
              Microsoft.Graph.Identity.DirectoryManagement,
              Microsoft.Graph.Users.Actions
    Graph permissions: User.ReadWrite.All, Group.ReadWrite.All,
                       Directory.ReadWrite.All, Mail.Send
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$UserPrincipalName,

    [Parameter(Mandatory = $false)]
    [bool]$RevokeSessions = $true,

    [Parameter(Mandatory = $false)]
    [bool]$ConvertToSharedMailbox = $false,

    [Parameter(Mandatory = $false)]
    [bool]$RemoveLicenses = $true,

    [Parameter(Mandatory = $false)]
    [bool]$BackupGroupMemberships = $true,

    [Parameter(Mandatory = $false)]
    [bool]$ManagerNotification = $true
)

$ErrorActionPreference = "Stop"
$LogPrefix = "[Remove-AzureADUser]"

# ---------------------------------------------------------------------------
# Result tracking
# ---------------------------------------------------------------------------
$result = @{
    UserPrincipalName      = $UserPrincipalName
    Success                = $false
    AccountDisabled        = $false
    SessionsRevoked        = $false
    GroupsRemoved          = 0
    GroupsBackedUp         = $false
    LicensesRemoved        = 0
    MailboxConverted       = $false
    ManagerNotified        = $false
    Errors                 = @()
    Timestamp              = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')
}

try {
    # ------------------------------------------------------------------
    # Connect to Microsoft Graph via Managed Identity
    # ------------------------------------------------------------------
    Write-Output "$LogPrefix Importing Microsoft.Graph modules..."
    Import-Module Microsoft.Graph.Users -Force
    Import-Module Microsoft.Graph.Groups -Force
    Import-Module Microsoft.Graph.Identity.DirectoryManagement -Force
    Import-Module Microsoft.Graph.Users.Actions -Force

    Write-Output "$LogPrefix Connecting to Microsoft Graph (Managed Identity)..."
    Connect-MgGraph -Identity -NoWelcome

    # ------------------------------------------------------------------
    # Resolve the user
    # ------------------------------------------------------------------
    Write-Output "$LogPrefix Resolving user: $UserPrincipalName"
    $user = Get-MgUser -UserId $UserPrincipalName -Property Id, DisplayName, UserPrincipalName, AccountEnabled
    if (-not $user) {
        throw "User not found: $UserPrincipalName"
    }
    $userId = $user.Id
    Write-Output "$LogPrefix Found user: $($user.DisplayName) ($userId)"

    # ------------------------------------------------------------------
    # 1. Disable the account
    # ------------------------------------------------------------------
    Write-Output "$LogPrefix Disabling account..."
    Update-MgUser -UserId $userId -AccountEnabled:$false
    $result.AccountDisabled = $true
    Write-Output "$LogPrefix Account disabled"

    # ------------------------------------------------------------------
    # 2. Revoke all sessions
    # ------------------------------------------------------------------
    if ($RevokeSessions) {
        Write-Output "$LogPrefix Revoking sign-in sessions..."
        try {
            Revoke-MgUserSignInSession -UserId $userId
            $result.SessionsRevoked = $true
            Write-Output "$LogPrefix All sessions revoked"
        }
        catch {
            $msg = "Failed to revoke sessions: $($_.Exception.Message)"
            Write-Warning "$LogPrefix $msg"
            $result.Errors += $msg
        }
    }

    # ------------------------------------------------------------------
    # 3. Get and backup group memberships
    # ------------------------------------------------------------------
    Write-Output "$LogPrefix Retrieving group memberships..."
    $groups = Get-MgUserMemberOf -UserId $userId -All | Where-Object {
        $_.'@odata.type' -eq '#microsoft.graph.group'
    }
    Write-Output "$LogPrefix User is a member of $($groups.Count) groups"

    if ($BackupGroupMemberships -and $groups.Count -gt 0) {
        try {
            $groupBackup = $groups | ForEach-Object {
                @{ GroupId = $_.Id; DisplayName = $_.AdditionalProperties.displayName }
            }
            $backupJson = $groupBackup | ConvertTo-Json -Compress
            $variableName = "Offboard_Groups_$($UserPrincipalName -replace '[^a-zA-Z0-9]', '_')"

            # Store in Automation variable for audit trail
            Set-AutomationVariable -Name $variableName -Value $backupJson
            $result.GroupsBackedUp = $true
            Write-Output "$LogPrefix Group memberships backed up to variable: $variableName"
        }
        catch {
            $msg = "Failed to backup groups: $($_.Exception.Message)"
            Write-Warning "$LogPrefix $msg"
            $result.Errors += $msg
        }
    }

    # ------------------------------------------------------------------
    # 4. Remove from all groups
    # ------------------------------------------------------------------
    if ($groups.Count -gt 0) {
        Write-Output "$LogPrefix Removing user from all groups..."
        foreach ($group in $groups) {
            try {
                Remove-MgGroupMemberByRef -GroupId $group.Id -DirectoryObjectId $userId
                $result.GroupsRemoved++
                Write-Output "$LogPrefix Removed from group: $($group.AdditionalProperties.displayName)"
            }
            catch {
                $msg = "Failed to remove from group $($group.Id): $($_.Exception.Message)"
                Write-Warning "$LogPrefix $msg"
                $result.Errors += $msg
            }
        }
    }

    # ------------------------------------------------------------------
    # 5. Remove licenses
    # ------------------------------------------------------------------
    if ($RemoveLicenses) {
        Write-Output "$LogPrefix Retrieving license assignments..."
        $userLicenses = Get-MgUserLicenseDetail -UserId $userId
        if ($userLicenses.Count -gt 0) {
            $skuIds = $userLicenses | ForEach-Object { $_.SkuId }
            Write-Output "$LogPrefix Removing $($skuIds.Count) license(s)..."
            try {
                Set-MgUserLicense -UserId $userId -AddLicenses @() -RemoveLicenses $skuIds
                $result.LicensesRemoved = $skuIds.Count
                Write-Output "$LogPrefix All licenses removed"
            }
            catch {
                $msg = "Failed to remove licenses: $($_.Exception.Message)"
                Write-Warning "$LogPrefix $msg"
                $result.Errors += $msg
            }
        }
        else {
            Write-Output "$LogPrefix No licenses assigned"
        }
    }

    # ------------------------------------------------------------------
    # 6. Convert mailbox to shared (Exchange Online)
    # ------------------------------------------------------------------
    if ($ConvertToSharedMailbox) {
        Write-Output "$LogPrefix Mailbox conversion to shared requested"
        try {
            # This requires the ExchangeOnlineManagement module.
            # If running in Azure Automation, ensure the module is imported.
            if (Get-Module -ListAvailable -Name ExchangeOnlineManagement) {
                Import-Module ExchangeOnlineManagement -Force
                Connect-ExchangeOnline -ManagedIdentity -Organization (($UserPrincipalName -split '@')[1])
                Set-Mailbox -Identity $UserPrincipalName -Type Shared
                Set-MailboxAutoReplyConfiguration -Identity $UserPrincipalName `
                    -AutoReplyState Enabled `
                    -InternalMessage "This person is no longer with the organisation. Please contact your manager or IT for assistance." `
                    -ExternalMessage "This person is no longer with the organisation. Please contact the main office for assistance."
                Disconnect-ExchangeOnline -Confirm:$false
                $result.MailboxConverted = $true
                Write-Output "$LogPrefix Mailbox converted to shared and OOO set"
            }
            else {
                $msg = "ExchangeOnlineManagement module not available. Mailbox conversion skipped."
                Write-Warning "$LogPrefix $msg"
                $result.Errors += $msg
            }
        }
        catch {
            $msg = "Mailbox conversion failed: $($_.Exception.Message)"
            Write-Warning "$LogPrefix $msg"
            $result.Errors += $msg
        }
    }

    # ------------------------------------------------------------------
    # 7. Notify manager
    # ------------------------------------------------------------------
    if ($ManagerNotification) {
        try {
            Write-Output "$LogPrefix Retrieving manager..."
            $manager = Get-MgUserManager -UserId $userId -ErrorAction SilentlyContinue
            if ($manager) {
                $managerUser = Get-MgUser -UserId $manager.Id -Property DisplayName, Mail
                if ($managerUser.Mail) {
                    $mailBody = @{
                        Message = @{
                            Subject = "Employee offboarded: $($user.DisplayName)"
                            Body    = @{
                                ContentType = "Text"
                                Content     = "This is an automated notification. The following user has been offboarded:`n`nName: $($user.DisplayName)`nUPN: $UserPrincipalName`nDate: $(Get-Date -Format 'yyyy-MM-dd HH:mm UTC')`n`nActions taken:`n- Account disabled`n- Sessions revoked: $($result.SessionsRevoked)`n- Groups removed: $($result.GroupsRemoved)`n- Licenses removed: $($result.LicensesRemoved)`n- Mailbox converted: $($result.MailboxConverted)`n`nPlease contact IT if you have questions."
                            }
                            ToRecipients = @(
                                @{
                                    EmailAddress = @{
                                        Address = $managerUser.Mail
                                    }
                                }
                            )
                        }
                        SaveToSentItems = $false
                    }
                    # Send as the offboarded user's mailbox (requires Mail.Send permission)
                    # Alternatively use a service account or shared mailbox
                    Send-MgUserMail -UserId $userId -BodyParameter $mailBody
                    $result.ManagerNotified = $true
                    Write-Output "$LogPrefix Manager notified: $($managerUser.DisplayName) ($($managerUser.Mail))"
                }
            }
            else {
                Write-Output "$LogPrefix No manager found for user"
            }
        }
        catch {
            $msg = "Manager notification failed: $($_.Exception.Message)"
            Write-Warning "$LogPrefix $msg"
            $result.Errors += $msg
        }
    }

    $result.Success = $true
    Write-Output "$LogPrefix Offboarding completed for $UserPrincipalName"
}
catch {
    $errorMsg = "$LogPrefix Critical error: $($_.Exception.Message)"
    Write-Error $errorMsg
    $result.Errors += $_.Exception.Message
    Write-Output "$LogPrefix Exception type: $($_.Exception.GetType().FullName)"
}
finally {
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
    }
    catch { }
}

# ---------------------------------------------------------------------------
# Output summary
# ---------------------------------------------------------------------------
Write-Output ""
Write-Output "=== Offboarding Summary ==="
Write-Output "User:              $UserPrincipalName"
Write-Output "Account disabled:  $($result.AccountDisabled)"
Write-Output "Sessions revoked:  $($result.SessionsRevoked)"
Write-Output "Groups removed:    $($result.GroupsRemoved)"
Write-Output "Groups backed up:  $($result.GroupsBackedUp)"
Write-Output "Licenses removed:  $($result.LicensesRemoved)"
Write-Output "Mailbox converted: $($result.MailboxConverted)"
Write-Output "Manager notified:  $($result.ManagerNotified)"
Write-Output "Errors:            $($result.Errors.Count)"
Write-Output "=========================="

return $result
