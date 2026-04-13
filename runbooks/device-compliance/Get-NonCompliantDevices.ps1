<#
.SYNOPSIS
    Generates a report of non-compliant and inactive Intune-managed devices.

.DESCRIPTION
    Queries Microsoft Graph for devices that are non-compliant or have not
    checked in within a specified number of days. Groups results by compliance
    state and OS platform, outputs a summary table, and optionally exports
    to CSV.

.PARAMETER ExportCsv
    Export results to a CSV file.

.PARAMETER EmailReport
    Send the report via email (requires Mail.Send Graph permission).

.PARAMETER NotificationEmail
    Email address to send the report to.

.PARAMETER DaysInactive
    Number of days without check-in to flag a device as inactive.

.EXAMPLE
    Get-NonCompliantDevices.ps1 -ExportCsv $true -DaysInactive 14

.NOTES
    Author:  Ariff Mohamed
    Version: 1.0
    Requires: Microsoft.Graph.DeviceManagement
    Graph permissions: DeviceManagementManagedDevices.Read.All, Mail.Send (if emailing)
#>

param(
    [Parameter(Mandatory = $false)]
    [bool]$ExportCsv = $true,

    [Parameter(Mandatory = $false)]
    [bool]$EmailReport = $false,

    [Parameter(Mandatory = $false)]
    [string]$NotificationEmail = "",

    [Parameter(Mandatory = $false)]
    [int]$DaysInactive = 30
)

$ErrorActionPreference = "Stop"
$LogPrefix = "[Get-NonCompliantDevices]"

try {
    # ------------------------------------------------------------------
    # Connect
    # ------------------------------------------------------------------
    Write-Output "$LogPrefix Importing modules..."
    Import-Module Microsoft.Graph.DeviceManagement -Force

    Write-Output "$LogPrefix Connecting to Microsoft Graph (Managed Identity)..."
    Connect-MgGraph -Identity -NoWelcome

    # ------------------------------------------------------------------
    # Query non-compliant devices
    # ------------------------------------------------------------------
    Write-Output "$LogPrefix Querying non-compliant devices..."
    $nonCompliantDevices = Get-MgDeviceManagementManagedDevice -Filter "complianceState ne 'compliant'" -All `
        -Property DeviceName, UserPrincipalName, OperatingSystem, OsVersion, ComplianceState, `
                  LastSyncDateTime, DeviceEnrollmentType, Model, Manufacturer, SerialNumber, `
                  Id, ComplianceGracePeriodExpirationDateTime

    Write-Output "$LogPrefix Found $($nonCompliantDevices.Count) non-compliant devices"

    # ------------------------------------------------------------------
    # Query inactive devices (not checked in for X days)
    # ------------------------------------------------------------------
    $cutoffDate = (Get-Date).AddDays(-$DaysInactive).ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Output "$LogPrefix Querying devices inactive since: $cutoffDate"

    $inactiveDevices = Get-MgDeviceManagementManagedDevice -Filter "lastSyncDateTime lt $cutoffDate" -All `
        -Property DeviceName, UserPrincipalName, OperatingSystem, OsVersion, ComplianceState, `
                  LastSyncDateTime, Model, Id

    Write-Output "$LogPrefix Found $($inactiveDevices.Count) inactive devices (>$DaysInactive days)"

    # ------------------------------------------------------------------
    # Build combined report
    # ------------------------------------------------------------------
    $report = [System.Collections.Generic.List[PSObject]]::new()

    foreach ($device in $nonCompliantDevices) {
        $report.Add([PSCustomObject]@{
            DeviceName       = $device.DeviceName
            UserPrincipalName = $device.UserPrincipalName
            OperatingSystem  = $device.OperatingSystem
            OsVersion        = $device.OsVersion
            ComplianceState  = $device.ComplianceState
            LastSyncDateTime = $device.LastSyncDateTime
            Model            = $device.Model
            Manufacturer     = $device.Manufacturer
            SerialNumber     = $device.SerialNumber
            DeviceId         = $device.Id
            Flag             = "NonCompliant"
        })
    }

    foreach ($device in $inactiveDevices) {
        # Avoid duplicates if a device is both non-compliant and inactive
        if ($report | Where-Object { $_.DeviceId -eq $device.Id }) { continue }
        $report.Add([PSCustomObject]@{
            DeviceName       = $device.DeviceName
            UserPrincipalName = $device.UserPrincipalName
            OperatingSystem  = $device.OperatingSystem
            OsVersion        = $device.OsVersion
            ComplianceState  = $device.ComplianceState
            LastSyncDateTime = $device.LastSyncDateTime
            Model            = $device.Model
            Manufacturer     = ""
            SerialNumber     = ""
            DeviceId         = $device.Id
            Flag             = "Inactive"
        })
    }

    # ------------------------------------------------------------------
    # Group summaries
    # ------------------------------------------------------------------
    Write-Output ""
    Write-Output "=== Compliance State Summary ==="
    $report | Group-Object -Property ComplianceState | ForEach-Object {
        Write-Output "  $($_.Name): $($_.Count)"
    }

    Write-Output ""
    Write-Output "=== OS Platform Summary ==="
    $report | Group-Object -Property OperatingSystem | ForEach-Object {
        Write-Output "  $($_.Name): $($_.Count)"
    }

    Write-Output ""
    Write-Output "=== Flag Summary ==="
    $report | Group-Object -Property Flag | ForEach-Object {
        Write-Output "  $($_.Name): $($_.Count)"
    }

    Write-Output ""
    Write-Output "Total devices in report: $($report.Count)"

    # ------------------------------------------------------------------
    # Export CSV
    # ------------------------------------------------------------------
    if ($ExportCsv) {
        $exportPath = Join-Path $env:TEMP "NonCompliantDevices_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $report | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
        Write-Output "CSV exported: $exportPath"
    }

    # ------------------------------------------------------------------
    # Email report
    # ------------------------------------------------------------------
    if ($EmailReport -and -not [string]::IsNullOrEmpty($NotificationEmail)) {
        try {
            Import-Module Microsoft.Graph.Users.Actions -Force

            $bodyLines = @("Device Compliance Report - $(Get-Date -Format 'yyyy-MM-dd')", "")
            $bodyLines += "Non-compliant devices: $($nonCompliantDevices.Count)"
            $bodyLines += "Inactive devices (>$DaysInactive days): $($inactiveDevices.Count)"
            $bodyLines += "Total flagged: $($report.Count)"
            $bodyLines += ""
            $bodyLines += "Top 20 devices:"
            $report | Select-Object -First 20 | ForEach-Object {
                $bodyLines += "  $($_.DeviceName) | $($_.UserPrincipalName) | $($_.ComplianceState) | $($_.LastSyncDateTime)"
            }

            # Uses a service account or automation mailbox to send
            $automationMailbox = Get-AutomationVariable -Name 'AutomationMailbox' -ErrorAction SilentlyContinue
            if ($automationMailbox) {
                $mailParams = @{
                    Message = @{
                        Subject      = "Device Compliance Report - $(Get-Date -Format 'yyyy-MM-dd')"
                        Body         = @{
                            ContentType = "Text"
                            Content     = ($bodyLines -join "`n")
                        }
                        ToRecipients = @(@{ EmailAddress = @{ Address = $NotificationEmail } })
                    }
                    SaveToSentItems = $false
                }
                Send-MgUserMail -UserId $automationMailbox -BodyParameter $mailParams
                Write-Output "Email sent to: $NotificationEmail"
            }
            else {
                Write-Warning "$LogPrefix AutomationMailbox variable not set. Email skipped."
            }
        }
        catch {
            Write-Warning "$LogPrefix Failed to send email: $($_.Exception.Message)"
        }
    }
}
catch {
    Write-Error "$LogPrefix Error: $($_.Exception.Message)"
    throw
}
finally {
    try { Disconnect-MgGraph -ErrorAction SilentlyContinue } catch { }
}
