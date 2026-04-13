<#
.SYNOPSIS
    Generates a Microsoft 365 license utilisation report showing consumed,
    purchased, and available counts per SKU.

.DESCRIPTION
    Retrieves all subscribed SKUs via Microsoft Graph, calculates utilisation
    percentages, flags SKUs at more than 90% capacity, and lists service plans
    per SKU. Exports a CSV summary and prints a formatted table.

.EXAMPLE
    Get-M365LicenseReport.ps1

.NOTES
    Author:  Ariff Mohamed
    Version: 1.0
    Requires: Microsoft.Graph.Identity.DirectoryManagement
    Graph permissions: Directory.Read.All, Organization.Read.All
#>

$ErrorActionPreference = "Stop"
$LogPrefix = "[Get-M365LicenseReport]"

try {
    # ------------------------------------------------------------------
    # Connect
    # ------------------------------------------------------------------
    Write-Output "$LogPrefix Importing modules..."
    Import-Module Microsoft.Graph.Identity.DirectoryManagement -Force

    Write-Output "$LogPrefix Connecting to Microsoft Graph (Managed Identity)..."
    Connect-MgGraph -Identity -NoWelcome

    # ------------------------------------------------------------------
    # Retrieve all subscribed SKUs
    # ------------------------------------------------------------------
    Write-Output "$LogPrefix Retrieving subscribed SKUs..."
    $skus = Get-MgSubscribedSku -All

    if ($skus.Count -eq 0) {
        Write-Output "$LogPrefix No subscribed SKUs found."
        return
    }

    Write-Output "$LogPrefix Found $($skus.Count) SKUs"

    # ------------------------------------------------------------------
    # Build report
    # ------------------------------------------------------------------
    $report = [System.Collections.Generic.List[PSObject]]::new()
    $warningSkus = [System.Collections.Generic.List[PSObject]]::new()

    foreach ($sku in $skus) {
        $purchased = $sku.PrepaidUnits.Enabled
        $consumed = $sku.ConsumedUnits
        $available = $purchased - $consumed
        $suspended = $sku.PrepaidUnits.Suspended
        $warning = $sku.PrepaidUnits.Warning

        $utilPct = if ($purchased -gt 0) { [math]::Round(($consumed / $purchased) * 100, 1) } else { 0 }

        $servicePlans = ($sku.ServicePlans | Where-Object { $_.ProvisioningStatus -eq 'Success' } |
            Select-Object -ExpandProperty ServicePlanName) -join '; '

        $entry = [PSCustomObject]@{
            SkuPartNumber    = $sku.SkuPartNumber
            SkuId            = $sku.SkuId
            Purchased        = $purchased
            Consumed         = $consumed
            Available        = $available
            Suspended        = $suspended
            Warning          = $warning
            UtilisationPct   = $utilPct
            CapStatus        = $sku.CapabilityStatus
            ServicePlans     = $servicePlans
        }

        $report.Add($entry)

        if ($utilPct -ge 90 -and $purchased -gt 0) {
            $warningSkus.Add($entry)
        }
    }

    # ------------------------------------------------------------------
    # Output formatted table
    # ------------------------------------------------------------------
    Write-Output ""
    Write-Output "=== Microsoft 365 License Utilisation Report ==="
    Write-Output "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm UTC')"
    Write-Output ""

    $report | Sort-Object UtilisationPct -Descending |
        Format-Table SkuPartNumber, Purchased, Consumed, Available, UtilisationPct, CapStatus -AutoSize |
        Out-String | Write-Output

    # ------------------------------------------------------------------
    # High utilisation warnings
    # ------------------------------------------------------------------
    if ($warningSkus.Count -gt 0) {
        Write-Output ""
        Write-Output "WARNING: The following SKUs are at 90% or higher utilisation:"
        Write-Output ""
        foreach ($w in $warningSkus) {
            Write-Output "  $($w.SkuPartNumber): $($w.Consumed)/$($w.Purchased) ($($w.UtilisationPct)%) -- $($w.Available) remaining"
        }
        Write-Output ""
    }
    else {
        Write-Output "All SKUs are below 90% utilisation."
    }

    # ------------------------------------------------------------------
    # Totals
    # ------------------------------------------------------------------
    $totalPurchased = ($report | Measure-Object -Property Purchased -Sum).Sum
    $totalConsumed = ($report | Measure-Object -Property Consumed -Sum).Sum
    $totalAvailable = ($report | Measure-Object -Property Available -Sum).Sum

    Write-Output ""
    Write-Output "=== Summary ==="
    Write-Output "Total SKUs:       $($report.Count)"
    Write-Output "Total purchased:  $totalPurchased"
    Write-Output "Total consumed:   $totalConsumed"
    Write-Output "Total available:  $totalAvailable"
    Write-Output "================"

    # ------------------------------------------------------------------
    # Export CSV
    # ------------------------------------------------------------------
    $exportPath = Join-Path $env:TEMP "M365LicenseReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $report | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
    Write-Output ""
    Write-Output "CSV exported: $exportPath"
}
catch {
    Write-Error "$LogPrefix Error: $($_.Exception.Message)"
    throw
}
finally {
    try { Disconnect-MgGraph -ErrorAction SilentlyContinue } catch { }
}
