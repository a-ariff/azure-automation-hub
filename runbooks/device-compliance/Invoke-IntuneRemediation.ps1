<#
.SYNOPSIS
    Triggers Intune device sync for non-compliant or specified devices.

.DESCRIPTION
    Sends a syncDevice action via the Microsoft Graph API to force non-compliant
    devices to check in. Supports targeting specific device IDs, all non-compliant
    devices, or filtering by OS platform. Includes rate limiting between batches.

.PARAMETER DeviceIds
    Array of Intune managed device IDs to sync. Optional if AllNonCompliant is set.

.PARAMETER AllNonCompliant
    Query and sync all non-compliant devices.

.PARAMETER OsPlatform
    Filter devices by OS platform (e.g. Windows, macOS, iOS, Android).

.PARAMETER BatchSize
    Number of devices to process per batch before pausing.

.PARAMETER BatchDelaySeconds
    Seconds to wait between batches to avoid throttling.

.EXAMPLE
    Invoke-IntuneRemediation.ps1 -AllNonCompliant $true -OsPlatform "Windows"

.EXAMPLE
    Invoke-IntuneRemediation.ps1 -DeviceIds @("device-id-1", "device-id-2")

.NOTES
    Author:  Ariff Mohamed
    Version: 1.0
    Requires: Microsoft.Graph.DeviceManagement, Microsoft.Graph.DeviceManagement.Actions
    Graph permissions: DeviceManagementManagedDevices.ReadWrite.All
#>

param(
    [Parameter(Mandatory = $false)]
    [string[]]$DeviceIds = @(),

    [Parameter(Mandatory = $false)]
    [bool]$AllNonCompliant = $false,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Windows", "macOS", "iOS", "Android", "")]
    [string]$OsPlatform = "",

    [Parameter(Mandatory = $false)]
    [int]$BatchSize = 50,

    [Parameter(Mandatory = $false)]
    [int]$BatchDelaySeconds = 10
)

$ErrorActionPreference = "Stop"
$LogPrefix = "[Invoke-IntuneRemediation]"

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if ($DeviceIds.Count -eq 0 -and -not $AllNonCompliant) {
    throw "Provide either -DeviceIds or set -AllNonCompliant to `$true."
}

$syncedCount = 0
$failedCount = 0
$failedDevices = [System.Collections.Generic.List[PSObject]]::new()

try {
    # ------------------------------------------------------------------
    # Connect
    # ------------------------------------------------------------------
    Write-Output "$LogPrefix Importing modules..."
    Import-Module Microsoft.Graph.DeviceManagement -Force

    Write-Output "$LogPrefix Connecting to Microsoft Graph (Managed Identity)..."
    Connect-MgGraph -Identity -NoWelcome

    # ------------------------------------------------------------------
    # Build device list
    # ------------------------------------------------------------------
    $targetDevices = @()

    if ($AllNonCompliant) {
        Write-Output "$LogPrefix Querying all non-compliant devices..."
        $filter = "complianceState ne 'compliant'"
        if (-not [string]::IsNullOrEmpty($OsPlatform)) {
            $filter += " and operatingSystem eq '$OsPlatform'"
        }
        $targetDevices = Get-MgDeviceManagementManagedDevice -Filter $filter -All `
            -Property Id, DeviceName, UserPrincipalName, OperatingSystem, ComplianceState
        Write-Output "$LogPrefix Found $($targetDevices.Count) non-compliant devices"
    }
    else {
        # Resolve provided IDs
        foreach ($id in $DeviceIds) {
            try {
                $device = Get-MgDeviceManagementManagedDevice -ManagedDeviceId $id `
                    -Property Id, DeviceName, UserPrincipalName, OperatingSystem, ComplianceState
                $targetDevices += $device
            }
            catch {
                Write-Warning "$LogPrefix Device not found: $id"
                $failedCount++
                $failedDevices.Add([PSCustomObject]@{
                    DeviceId = $id
                    DeviceName = "Unknown"
                    Error = "Device not found"
                })
            }
        }
        Write-Output "$LogPrefix Resolved $($targetDevices.Count) devices from provided IDs"
    }

    if ($targetDevices.Count -eq 0) {
        Write-Output "$LogPrefix No devices to sync. Exiting."
        return
    }

    # ------------------------------------------------------------------
    # OS filter (for DeviceIds mode)
    # ------------------------------------------------------------------
    if (-not $AllNonCompliant -and -not [string]::IsNullOrEmpty($OsPlatform)) {
        $before = $targetDevices.Count
        $targetDevices = $targetDevices | Where-Object { $_.OperatingSystem -eq $OsPlatform }
        Write-Output "$LogPrefix Filtered by $OsPlatform : $before -> $($targetDevices.Count) devices"
    }

    # ------------------------------------------------------------------
    # Sync devices in batches
    # ------------------------------------------------------------------
    $total = $targetDevices.Count
    $batchNumber = 0

    for ($i = 0; $i -lt $total; $i += $BatchSize) {
        $batchNumber++
        $batch = $targetDevices | Select-Object -Skip $i -First $BatchSize
        Write-Output "$LogPrefix Processing batch $batchNumber ($($batch.Count) devices)..."

        foreach ($device in $batch) {
            try {
                # POST /deviceManagement/managedDevices/{id}/syncDevice
                $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$($device.Id)/syncDevice"
                Invoke-MgGraphRequest -Method POST -Uri $uri
                $syncedCount++
                Write-Output "$LogPrefix Synced: $($device.DeviceName) ($($device.Id))"
            }
            catch {
                $failedCount++
                $failedDevices.Add([PSCustomObject]@{
                    DeviceId   = $device.Id
                    DeviceName = $device.DeviceName
                    Error      = $_.Exception.Message
                })
                Write-Warning "$LogPrefix Failed to sync $($device.DeviceName): $($_.Exception.Message)"
            }
        }

        # Rate limiting between batches
        if (($i + $BatchSize) -lt $total) {
            Write-Output "$LogPrefix Waiting $BatchDelaySeconds seconds before next batch..."
            Start-Sleep -Seconds $BatchDelaySeconds
        }
    }
}
catch {
    Write-Error "$LogPrefix Critical error: $($_.Exception.Message)"
    throw
}
finally {
    try { Disconnect-MgGraph -ErrorAction SilentlyContinue } catch { }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Output ""
Write-Output "=== Intune Remediation Summary ==="
Write-Output "Total targeted:  $($targetDevices.Count)"
Write-Output "Synced:          $syncedCount"
Write-Output "Failed:          $failedCount"
if ($failedDevices.Count -gt 0) {
    Write-Output ""
    Write-Output "Failed devices:"
    $failedDevices | ForEach-Object {
        Write-Output "  $($_.DeviceName) ($($_.DeviceId)): $($_.Error)"
    }
}
Write-Output "=================================="
