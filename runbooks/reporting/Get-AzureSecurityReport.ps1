<#
.SYNOPSIS
    Generates a security posture report covering Defender secure score, PIM,
    Conditional Access policies, and MFA registration status.

.DESCRIPTION
    Queries Microsoft Graph for security-related data points across the tenant
    and outputs a formatted report. Optionally exports to a markdown file in
    the automation storage account.

.EXAMPLE
    Get-AzureSecurityReport.ps1

.NOTES
    Author:  Ariff Mohamed
    Version: 1.0
    Requires: Microsoft.Graph.Security, Microsoft.Graph.Identity.SignIns,
              Microsoft.Graph.Identity.Governance
    Graph permissions: SecurityEvents.Read.All, Policy.Read.All,
                       RoleManagement.Read.Directory, Reports.Read.All,
                       UserAuthenticationMethod.Read.All
#>

$ErrorActionPreference = "Stop"
$LogPrefix = "[Get-AzureSecurityReport]"

$reportLines = [System.Collections.Generic.List[string]]::new()

function Add-Section {
    param([string]$Title)
    $reportLines.Add("")
    $reportLines.Add("## $Title")
    $reportLines.Add("")
}

try {
    # ------------------------------------------------------------------
    # Connect
    # ------------------------------------------------------------------
    Write-Output "$LogPrefix Importing modules..."
    Import-Module Microsoft.Graph.Security -Force -ErrorAction SilentlyContinue
    Import-Module Microsoft.Graph.Identity.SignIns -Force -ErrorAction SilentlyContinue
    Import-Module Microsoft.Graph.Identity.Governance -Force -ErrorAction SilentlyContinue

    Write-Output "$LogPrefix Connecting to Microsoft Graph (Managed Identity)..."
    Connect-MgGraph -Identity -NoWelcome

    $reportDate = Get-Date -Format 'yyyy-MM-dd HH:mm UTC'
    $reportLines.Add("# Azure Security Posture Report")
    $reportLines.Add("Generated: $reportDate")

    # ------------------------------------------------------------------
    # 1. Defender for Cloud Secure Score
    # ------------------------------------------------------------------
    Add-Section "Microsoft Defender Secure Score"

    try {
        $uri = "https://graph.microsoft.com/v1.0/security/secureScores?`$top=1"
        $secureScoreResponse = Invoke-MgGraphRequest -Method GET -Uri $uri
        $secureScore = $secureScoreResponse.value | Select-Object -First 1

        if ($secureScore) {
            $currentScore = $secureScore.currentScore
            $maxScore = $secureScore.maxScore
            $percentage = if ($maxScore -gt 0) { [math]::Round(($currentScore / $maxScore) * 100, 1) } else { 0 }
            $reportLines.Add("Current score: $currentScore / $maxScore ($percentage%)")
            $reportLines.Add("Date: $($secureScore.createdDateTime)")

            # Top control scores
            if ($secureScore.controlScores) {
                $reportLines.Add("")
                $reportLines.Add("Top improvement actions:")
                $improvements = $secureScore.controlScores | Where-Object { $_.score -lt $_.maxScore } |
                    Sort-Object { $_.maxScore - $_.score } -Descending | Select-Object -First 10
                foreach ($ctrl in $improvements) {
                    $gap = $ctrl.maxScore - $ctrl.score
                    $reportLines.Add("  - $($ctrl.controlName): $($ctrl.score)/$($ctrl.maxScore) (potential gain: $gap)")
                }
            }
        }
        else {
            $reportLines.Add("No secure score data available.")
        }
    }
    catch {
        $reportLines.Add("Error retrieving secure score: $($_.Exception.Message)")
        Write-Warning "$LogPrefix Secure score query failed: $($_.Exception.Message)"
    }

    # ------------------------------------------------------------------
    # 2. PIM Eligible Assignments
    # ------------------------------------------------------------------
    Add-Section "Privileged Identity Management (PIM)"

    try {
        $uri = "https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilityScheduleInstances"
        $pimResponse = Invoke-MgGraphRequest -Method GET -Uri $uri
        $eligibleAssignments = $pimResponse.value

        $reportLines.Add("Total eligible role assignments: $($eligibleAssignments.Count)")

        if ($eligibleAssignments.Count -gt 0) {
            # Group by role
            $byRole = $eligibleAssignments | Group-Object -Property roleDefinitionId
            $reportLines.Add("")
            $reportLines.Add("Eligible assignments by role:")
            foreach ($roleGroup in $byRole) {
                try {
                    $roleUri = "https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions/$($roleGroup.Name)"
                    $roleDef = Invoke-MgGraphRequest -Method GET -Uri $roleUri
                    $reportLines.Add("  - $($roleDef.displayName): $($roleGroup.Count) principals")
                }
                catch {
                    $reportLines.Add("  - Role $($roleGroup.Name): $($roleGroup.Count) principals")
                }
            }
        }
    }
    catch {
        $reportLines.Add("Error retrieving PIM data: $($_.Exception.Message)")
        Write-Warning "$LogPrefix PIM query failed: $($_.Exception.Message)"
    }

    # ------------------------------------------------------------------
    # 3. Conditional Access Policies
    # ------------------------------------------------------------------
    Add-Section "Conditional Access Policies"

    try {
        $uri = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies"
        $caResponse = Invoke-MgGraphRequest -Method GET -Uri $uri
        $policies = $caResponse.value

        $enabled = ($policies | Where-Object { $_.state -eq 'enabled' }).Count
        $reportOnly = ($policies | Where-Object { $_.state -eq 'enabledForReportingButNotEnforced' }).Count
        $disabled = ($policies | Where-Object { $_.state -eq 'disabled' }).Count

        $reportLines.Add("Total policies:  $($policies.Count)")
        $reportLines.Add("Enabled:         $enabled")
        $reportLines.Add("Report-only:     $reportOnly")
        $reportLines.Add("Disabled:        $disabled")
        $reportLines.Add("")
        $reportLines.Add("Policy list:")

        foreach ($policy in ($policies | Sort-Object { $_.state })) {
            $reportLines.Add("  - [$($policy.state)] $($policy.displayName)")
        }
    }
    catch {
        $reportLines.Add("Error retrieving CA policies: $($_.Exception.Message)")
        Write-Warning "$LogPrefix CA policy query failed: $($_.Exception.Message)"
    }

    # ------------------------------------------------------------------
    # 4. MFA Registration Status
    # ------------------------------------------------------------------
    Add-Section "MFA Registration Status"

    try {
        $uri = "https://graph.microsoft.com/v1.0/reports/authenticationMethods/userRegistrationDetails"
        $mfaResponse = Invoke-MgGraphRequest -Method GET -Uri $uri
        $registrations = $mfaResponse.value

        $total = $registrations.Count
        $mfaRegistered = ($registrations | Where-Object { $_.isMfaRegistered -eq $true }).Count
        $mfaCapable = ($registrations | Where-Object { $_.isMfaCapable -eq $true }).Count
        $passwordless = ($registrations | Where-Object { $_.isPasswordlessCapable -eq $true }).Count

        $mfaPct = if ($total -gt 0) { [math]::Round(($mfaRegistered / $total) * 100, 1) } else { 0 }

        $reportLines.Add("Total users:             $total")
        $reportLines.Add("MFA registered:          $mfaRegistered ($mfaPct%)")
        $reportLines.Add("MFA capable:             $mfaCapable")
        $reportLines.Add("Passwordless capable:    $passwordless")

        # Methods breakdown
        $reportLines.Add("")
        $reportLines.Add("Authentication methods registered:")
        $allMethods = $registrations | ForEach-Object { $_.methodsRegistered } | Where-Object { $_ }
        $allMethods | Group-Object | Sort-Object Count -Descending | ForEach-Object {
            $reportLines.Add("  - $($_.Name): $($_.Count)")
        }
    }
    catch {
        $reportLines.Add("Error retrieving MFA data: $($_.Exception.Message)")
        Write-Warning "$LogPrefix MFA query failed: $($_.Exception.Message)"
    }

    # ------------------------------------------------------------------
    # Output report
    # ------------------------------------------------------------------
    $fullReport = $reportLines -join "`n"
    Write-Output $fullReport

    # ------------------------------------------------------------------
    # Export to file
    # ------------------------------------------------------------------
    $exportPath = Join-Path $env:TEMP "AzureSecurityReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').md"
    $fullReport | Out-File -FilePath $exportPath -Encoding UTF8
    Write-Output ""
    Write-Output "$LogPrefix Report exported to: $exportPath"
}
catch {
    Write-Error "$LogPrefix Critical error: $($_.Exception.Message)"
    throw
}
finally {
    try { Disconnect-MgGraph -ErrorAction SilentlyContinue } catch { }
}
