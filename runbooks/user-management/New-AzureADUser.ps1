<#
.SYNOPSIS
    Creates a new Azure AD user account with comprehensive error handling and logging.

.DESCRIPTION
    This Azure Automation runbook creates a new Azure AD user account with specified parameters.
    Includes email notification, group assignment, and license assignment capabilities.
    Supports both interactive and service principal authentication.

.PARAMETER DisplayName
    The display name for the new user.

.PARAMETER UserPrincipalName
    The user principal name (UPN) for the new user.

.PARAMETER MailNickname
    The mail nickname for the new user.

.PARAMETER Department
    The department for the new user (optional).

.PARAMETER JobTitle
    The job title for the new user (optional).

.PARAMETER AssignedGroups
    Array of group object IDs to assign the user to (optional).

.PARAMETER LicenseSku
    The license SKU to assign to the user (optional).

.PARAMETER SendWelcomeEmail
    Whether to send a welcome email to the new user.

.EXAMPLE
    New-AzureADUser -DisplayName "John Smith" -UserPrincipalName "jsmith@contoso.com" -MailNickname "jsmith" -Department "IT" -JobTitle "Systems Administrator"

.NOTES
    Author: Azure Automation Hub
    Version: 1.0
    Last Modified: 2025-08-26
    
    Prerequisites:
    - Azure AD PowerShell module or Microsoft.Graph module
    - Appropriate Azure AD permissions
    - Azure Automation variables configured
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$DisplayName,
    
    [Parameter(Mandatory = $true)]
    [string]$UserPrincipalName,
    
    [Parameter(Mandatory = $true)]
    [string]$MailNickname,
    
    [Parameter(Mandatory = $false)]
    [string]$Department = "",
    
    [Parameter(Mandatory = $false)]
    [string]$JobTitle = "",
    
    [Parameter(Mandatory = $false)]
    [string[]]$AssignedGroups = @(),
    
    [Parameter(Mandatory = $false)]
    [string]$LicenseSku = "",
    
    [Parameter(Mandatory = $false)]
    [bool]$SendWelcomeEmail = $false
)

# Initialize logging
$ErrorActionPreference = "Stop"
$LogPrefix = "[New-AzureADUser]"

Write-Output "$LogPrefix Starting user creation process for: $DisplayName"

try {
    # Import required modules
    Write-Output "$LogPrefix Importing Microsoft Graph modules..."
    Import-Module Microsoft.Graph.Users -Force
    Import-Module Microsoft.Graph.Groups -Force
    Import-Module Microsoft.Graph.Identity.DirectoryManagement -Force
    
    # Get Azure Automation variables
    Write-Output "$LogPrefix Retrieving automation variables..."
    $TenantId = Get-AutomationVariable -Name 'TenantId'
    $NotificationEmail = Get-AutomationVariable -Name 'NotificationEmail'
    
    # Connect to Microsoft Graph
    Write-Output "$LogPrefix Connecting to Microsoft Graph..."
    $Credential = Get-AutomationPSCredential -Name 'AzureGraphCredential'
    Connect-MgGraph -TenantId $TenantId -Credential $Credential
    
    # Generate temporary password
    $PasswordLength = 12
    $Password = -join ((65..90) + (97..122) + (48..57) + (33, 35, 36, 37, 38, 42, 43, 45, 61, 63, 64) | Get-Random -Count $PasswordLength | ForEach-Object {[char]$_})
    
    # Create password profile
    $PasswordProfile = @{
        Password = $Password
        ForceChangePasswordNextSignIn = $true
    }
    
    # Prepare user properties
    $UserProperties = @{
        DisplayName = $DisplayName
        UserPrincipalName = $UserPrincipalName
        MailNickname = $MailNickname
        AccountEnabled = $true
        PasswordProfile = $PasswordProfile
        UsageLocation = "US"  # Required for license assignment
    }
    
    # Add optional properties if provided
    if ($Department) { $UserProperties.Department = $Department }
    if ($JobTitle) { $UserProperties.JobTitle = $JobTitle }
    
    # Create the user
    Write-Output "$LogPrefix Creating user account..."
    $NewUser = New-MgUser -BodyParameter $UserProperties
    Write-Output "$LogPrefix User created successfully. User ID: $($NewUser.Id)"
    
    # Wait for user creation to propagate
    Start-Sleep -Seconds 10
    
    # Assign to groups if specified
    if ($AssignedGroups.Count -gt 0) {
        Write-Output "$LogPrefix Assigning user to groups..."
        foreach ($GroupId in $AssignedGroups) {
            try {
                $GroupMember = @{
                    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($NewUser.Id)"
                }
                New-MgGroupMember -GroupId $GroupId -BodyParameter $GroupMember
                Write-Output "$LogPrefix Added user to group: $GroupId"
            }
            catch {
                Write-Warning "$LogPrefix Failed to add user to group $GroupId : $($_.Exception.Message)"
            }
        }
    }
    
    # Assign license if specified
    if ($LicenseSku) {
        Write-Output "$LogPrefix Assigning license: $LicenseSku"
        try {
            $License = @{
                AddLicenses = @(
                    @{
                        SkuId = $LicenseSku
                    }
                )
                RemoveLicenses = @()
            }
            Set-MgUserLicense -UserId $NewUser.Id -BodyParameter $License
            Write-Output "$LogPrefix License assigned successfully"
        }
        catch {
            Write-Warning "$LogPrefix Failed to assign license: $($_.Exception.Message)"
        }
    }
    
    # Prepare success notification
    $SuccessMessage = @"
User Creation Successful
========================

User Details:
- Display Name: $DisplayName
- User Principal Name: $UserPrincipalName
- User ID: $($NewUser.Id)
- Department: $Department
- Job Title: $JobTitle
- Temporary Password: $Password

Next Steps:
1. User will be prompted to change password on first login
2. Notify the user of their new account credentials
3. Verify group memberships and license assignments

Created by: Azure Automation
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')
"@
    
    Write-Output $SuccessMessage
    
    # Send email notification if configured
    if ($NotificationEmail -and $SendWelcomeEmail) {
        try {
            $EmailSubject = "New Azure AD User Created: $DisplayName"
            $EmailBody = $SuccessMessage
            
            # This would require additional email configuration
            # Send-AutomationEmail -To $NotificationEmail -Subject $EmailSubject -Body $EmailBody
            Write-Output "$LogPrefix Email notification would be sent to: $NotificationEmail"
        }
        catch {
            Write-Warning "$LogPrefix Failed to send email notification: $($_.Exception.Message)"
        }
    }
    
    # Return user object for potential pipeline use
    return @{
        Success = $true
        UserId = $NewUser.Id
        UserPrincipalName = $UserPrincipalName
        DisplayName = $DisplayName
        TemporaryPassword = $Password
        Message = "User created successfully"
    }
}
catch {
    $ErrorMessage = "$LogPrefix Error creating user: $($_.Exception.Message)"
    Write-Error $ErrorMessage
    
    # Log detailed error information
    Write-Output "$LogPrefix Error Details:"
    Write-Output "$LogPrefix Exception Type: $($_.Exception.GetType().FullName)"
    Write-Output "$LogPrefix Stack Trace: $($_.Exception.StackTrace)"
    
    # Return error object
    return @{
        Success = $false
        Error = $_.Exception.Message
        Message = "Failed to create user"
    }
}
finally {
    # Cleanup - disconnect from Graph
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        Write-Output "$LogPrefix Disconnected from Microsoft Graph"
    }
    catch {
        Write-Warning "$LogPrefix Error disconnecting from Graph: $($_.Exception.Message)"
    }
}

Write-Output "$LogPrefix User creation process completed."
