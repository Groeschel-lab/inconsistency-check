<#
.SYNOPSIS
    Measure end-to-end deployment time of the Inconsistency Check stack.

.DESCRIPTION
    Provisions the complete system from code into fresh resource groups N times,
    timing three milestones per run:
      - arm     : deployment command start -> ARM reports "Succeeded"
      - health  : ... -> GET /api/health returns 200 (app serving)
      - analyze : ... -> POST /api/analyze returns 200 (first successful model
                  call, i.e. RBAC has propagated and the model is reachable over
                  the private endpoint)
    After each run the resource group is DELETED and the model account is purged
    so model quota is freed for the next run. Prints mean +/- SD and writes a
    JSON report.

    PREREQUISITES (same as a normal 1-click deploy):
      - Azure CLI logged in (az login) to the target tenant/subscription
      - Owner, or Contributor + User Access Administrator, at subscription scope
        (the template creates RBAC role assignments)
      - Quota for the chosen model in the chosen region
      - PowerShell 7+ and curl

    WARNING: this script CREATES and DELETES resource groups named
    "rg-logiccheck-<Prefix><i>". Do not point -Prefix at anything you keep.

.EXAMPLE
    pwsh scripts/measure-deploy-time.ps1 -N 3 -Model claude-opus-4-7 -Region swedencentral
#>
[CmdletBinding()]
param(
    [int]$N = 3,
    [ValidateSet('claude-opus-4-7', 'gpt-5.5', 'mistral-large-3', 'deepseek-v3.2', 'gpt-5.4-nano')]
    [string]$Model = 'claude-opus-4-7',
    [ValidateSet('swedencentral', 'germanywestcentral', 'switzerlandnorth')]
    [string]$Region = 'swedencentral',
    [string]$Prefix = 'bm',
    [string]$TemplateFile = (Join-Path $PSScriptRoot '..' 'infra' 'main.json'),
    [string]$OutFile = (Join-Path (Get-Location) 'deploy-timing.json')
)

$ErrorActionPreference = 'Continue'
if (-not (Test-Path $TemplateFile)) { throw "Template not found: $TemplateFile" }

# PHI-free synthetic probe (internal contradiction: diabetes + high HbA1c, no therapy).
$probe = '{"text":"Diagnose: Diabetes mellitus Typ 2. HbA1c 9,4 Prozent. Entlassung ohne antidiabetische Therapie."}'
$probeFile = Join-Path ([System.IO.Path]::GetTempPath()) 'lc_probe.json'
$probe | Set-Content -Path $probeFile -Encoding ascii

Write-Host "Measuring $N deployment(s): model=$Model region=$Region prefix=$Prefix" -ForegroundColor Cyan
Write-Host "This creates and DELETES resource groups rg-logiccheck-$Prefix<1..$N>." -ForegroundColor Yellow

$runs = New-Object System.Collections.ArrayList

for ($i = 1; $i -le $N; $i++) {
    $sfx = "$Prefix$i"
    $rg = "rg-logiccheck-$sfx"
    $url = "https://func-lc-$sfx.azurewebsites.net"

    # Clean any prior remnants of this suffix.
    az group delete -n $rg --yes 2>$null | Out-Null
    az cognitiveservices account purge --location $Region --resource-group $rg --name "aif-$sfx" 2>$null | Out-Null

    $rec = [ordered]@{ run = $i; suffix = $sfx; state = $null; arm_s = $null; health_s = $null; analyze_s = $null }
    $t0 = Get-Date
    az deployment sub create --location $Region --name "lc-$sfx" --template-file $TemplateFile `
        --parameters nameSuffix=$sfx modelProfile=$Model -o none 2>$null
    $armOk = ($LASTEXITCODE -eq 0)
    $rec.arm_s = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
    $rec.state = if ($armOk) { 'Succeeded' } else { 'Failed' }

    if ($armOk) {
        curl.exe -s -o NUL -m 10 --retry 60 --retry-delay 5 --retry-all-errors -f "$url/api/health" 2>$null
        if ($LASTEXITCODE -eq 0) { $rec.health_s = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1) }
        curl.exe -s -o NUL -m 60 --retry 120 --retry-delay 5 --retry-all-errors -f -X POST "$url/api/analyze" `
            -H 'Content-Type: application/json' --data "@$probeFile" 2>$null
        if ($LASTEXITCODE -eq 0) { $rec.analyze_s = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1) }
    }

    [void]$runs.Add([pscustomobject]$rec)
    Write-Host ("  run {0}: {1}  arm={2}s health={3}s analyze={4}s" -f `
            $i, $rec.state, $rec.arm_s, $rec.health_s, $rec.analyze_s)

    # Teardown (synchronous) then purge so model quota is free for the next run.
    az group delete -n $rg --yes 2>$null | Out-Null
    az cognitiveservices account purge --location $Region --resource-group $rg --name "aif-$sfx" 2>$null | Out-Null
}

function Get-Stat($vals) {
    $v = @($vals | Where-Object { $_ -ne $null })
    if ($v.Count -eq 0) { return [ordered]@{ n = 0; mean = $null; sd = $null } }
    $m = ($v | Measure-Object -Average).Average
    $sd = if ($v.Count -gt 1) {
        [math]::Sqrt((($v | ForEach-Object { ($_ - $m) * ($_ - $m) }) | Measure-Object -Sum).Sum / ($v.Count - 1))
    }
    else { 0 }
    return [ordered]@{ n = $v.Count; mean = [math]::Round($m, 1); sd = [math]::Round($sd, 1) }
}

$summary = [ordered]@{
    model   = $Model
    region  = $Region
    n       = $N
    arm     = (Get-Stat ($runs.arm_s))
    health  = (Get-Stat ($runs.health_s))
    analyze = (Get-Stat ($runs.analyze_s))
    runs    = $runs
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -Path $OutFile -Encoding ascii

Write-Host ""
Write-Host "Summary (seconds, mean +/- SD):" -ForegroundColor Cyan
Write-Host ("  ARM provisioning      : {0} +/- {1}  (n={2})" -f $summary.arm.mean, $summary.arm.sd, $summary.arm.n)
Write-Host ("  to /api/health 200    : {0} +/- {1}  (n={2})" -f $summary.health.mean, $summary.health.sd, $summary.health.n)
Write-Host ("  to first /api/analyze : {0} +/- {1}  (n={2})" -f $summary.analyze.mean, $summary.analyze.sd, $summary.analyze.n)
Write-Host "Report written to $OutFile"
