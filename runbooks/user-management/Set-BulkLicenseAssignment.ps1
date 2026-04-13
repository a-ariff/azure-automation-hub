<#
.SYNOPSIS
    Assigns or removes Microsoft 365 licenses in bulk from a CSV or group membership.

.DESCRIPTION
    Reads a list of users from a CSV file (column: UserPrincipalName) or from an
    Entra ID group's members, then assigns or swaps licenses using Microsoft.Graph.
    Reports success/failure counts and exports results to a temp file.

.PARAMETER CsvPath
    Path to a CSV file with a UserPrincipalName column. Mutually exclusive with GroupId.

.PARAMETER GroupId
    Object ID of an Entra ID group. All members will receive the license.

.PARAMETER LicenseSkuId
    SKU ID of the license to assign (e.g. the GUID from Get-MgSubscribedSku).

.PARAMETER RemoveLicenseSkuId
    Optional SKU ID of a license to remove (for license swaps).

.EXAMPLE
    Set-BulkLicenseAssignment.ps1 -CsvPath "C:\users.csv" -LicenseSkuId "05e9a617-0261-4cee-bb44-138d3ef5d965"

.EXAMPLE
    Set-BulkLicenseAssignment.ps1 -GroupId "a1b2c3d4-..." -LicenseSkuId "05e9a617-..." -RemoveLicenseSkuId "c7df2760-..."

.NOTES
    Author:  Ariff Mohamed
    Version: 1.0
    Requires: Microsoft.Graph.Users, Microsoft.Graph.Groups, Microsoft.Graph.Identity.DirectoryManagement
    Graph permissions: User.ReadWrite.All, Group.Read.All, Directory.Read.All
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$CsvPath = "",

    [Parameter(Mandatory = $false)]
    [string]$GroupId = "",

    [Parameter(Mandatory = $true)]
    [string]$LicenseSkuId,

    [Parameter(Mandatory = $false)]
    [string]$RemoveLicenseSkuId = ""
)

$ErrorActionPreference = "Stop"
$LogPrefix = "[Set-BulkLicenseAssignment]"

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if ([string]::IsNullOrEmpty($CsvPath) -and [string]::IsNullOrEmpty($GroupId)) {
    throw "You must provide either -CsvPath or -GroupId."
}
if (-not [string]::IsNullOrEmpty($CsvPath) -and -not [string]::IsNullOrEmpty($GroupId)) {
    throw "Provide only one of -CsvPath or -GroupId, not both."
}

# ---------------------------------------------------------------------------
# Results tracking
# ---------------------------------------------------------------------------
$results = [System.Collections.Generic.List[PSObject]]::new()
$successCount = 0
$failCount = 0
$skipCount = 0

try {
    # ------------------------------------------------------------------
    # Connect
    # ------------------------------------------------------------------
    Write-Output "$LogPrefix Importing modules..."
    Import-Module Microsoft.Graph.Users -Force
    Import-Module Microsoft.Graph.Groups -Force
    Import-Module Microsoft.Graph.Identity.DirectoryManagement -Force

    Write-Output "$LogPrefix Connecting to Microsoft Graph (Managed Identity)..."
    Connect-MgGraph -Identity -NoWelcome

    # ------------------------------------------------------------------
    # Build user list
    # ------------------------------------------------------------------
    $users = @()

    if (-not [string]::IsNullOrEmpty($CsvPath)) {
        Write-Output "$LogPrefix Reading CSV: $CsvPath"
        if (-not (Test-Path $CsvPath)) {
            throw "CSV file not found: $CsvPath"
        }
        $csvData = Import-Csv -Path $CsvPath
        if (-not ($csvData | Get-Member -Name 'UserPrincipalName' -ErrorAction SilentlyContinue)) {
            throw "CSV must contain a 'UserPrincipalName' column."
        }
        $users = $csvData | Select-Object -ExpandProperty UserPrincipalName
    }
    else {
        Write-Output "$LogPrefix Retrieving members of group: $GroupId"
        $members = Get-MgGroupMember -GroupId $GroupId -All
        $users = $members | ForEach-Object {
            (Get-MgUser -UserId $_.Id -Property UserPrincipalName).UserPrincipalName
        }
    }

    Write-Output "$LogPrefix Processing $($users.Count) users"

    # ------------------------------------------------------------------
    # Validate SKU availability
    # ------------------------------------------------------------------
    Write-Output "$LogPrefix Verifying license SKU availability..."
    $subscribedSkus = Get-MgSubscribedSku -All
    $targetSku = $subscribedSkus | Where-Object { $_.SkuId -eq $LicenseSkuId }
    if (-not $targetSku) {
        throw "License SKU not found in tenant: $LicenseSkuId"
    }
    $available = $targetSku.PrepaidUnits.Enabled - $targetSku.ConsumedUnits
    Write-Output "$LogPrefix SKU: $($targetSku.SkuPartNumber) -- Available: $available / $($targetSku.PrepaidUnits.Enabled)"

    if ($available -lt $users.Count) {
        Write-Warning "$LogPrefix Not enough licenses. Available: $available, Requested: $($users.Count)"
    }

    # ------------------------------------------------------------------
    # Process each user
    # ------------------------------------------------------------------
    foreach ($upn in $users) {
        $entry = [PSCustomObject]@{
            UserPrincipalName = $upn
            Status            = ""
            Error             = ""
        }

        try {
            $addLicenses = @(@{ SkuId = $LicenseSkuId })
            $removeLicenses = @()

            if (-not [string]::IsNullOrEmpty($RemoveLicenseSkuId)) {
                $removeLicenses = @($RemoveLicenseSkuId)
            }

            Set-MgUserLicense -UserId $upn -AddLicenses $addLicenses -RemoveLicenses $removeLicenses
            $entry.Status = "Success"
            $successCount++
            Write-Output "$LogPrefix [$successCount] Assigned license to: $upn"
        }
        catch {
            $entry.Status = "Failed"
            $entry.Error = $_.Exception.Message
            $failCount++
            Write-Warning "$LogPrefix Failed for $upn : $($_.Exception.Message)"
        }

        $results.Add($entry)
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
# Export results
# ---------------------------------------------------------------------------
$exportPath = Join-Path $env:TEMP "BulkLicenseAssignment_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$results | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
Write-Output ""
Write-Output "=== Bulk License Assignment Summary ==="
Write-Output "Total users:  $($results.Count)"
Write-Output "Succeeded:    $successCount"
Write-Output "Failed:       $failCount"
Write-Output "Results file: $exportPath"
Write-Output "========================================"
