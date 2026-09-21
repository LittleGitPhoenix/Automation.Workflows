<#PSScriptInfo
.VERSION 1.0.0
.GUID a9b4e4e6-2097-4ea1-bb7a-10aed760b806
.AUTHOR Felix Leistner
.COMPANYNAME Little Phoenix
.COPYRIGHT 2026 Little Phoenix
.TAGS ci cd powershell
.PROJECTURI https://github.com/LittleGitPhoenix/Automation.Workflows
#>

#Requires -Version 7
<#
.SYNOPSIS
    Detects prerelease NuGet package dependencies (alpha/beta/rc/preview) via `dotnet list package --format json`.
#>
param(
    [string] $WorkspaceRoot = [System.IO.Path]::GetFullPath("$PSScriptRoot/../.."),
    [string] $ConfigPath,
    [string] $SummaryFile
)

$ErrorActionPreference = 'Stop'

$config       = & "$PSScriptRoot/Get-CiConfig.ps1" -WorkspaceRoot $WorkspaceRoot -ConfigPath $ConfigPath
$solutionPath = Join-Path $WorkspaceRoot $config.solutionPath

Write-Host 'Checking for prerelease NuGet packages...' -ForegroundColor Cyan

$jsonText = & dotnet list $solutionPath package --format json --include-transitive
if ($LASTEXITCODE -ne 0) {
    Write-Host '❌ dotnet list package failed.' -ForegroundColor Red
    exit 1
}

try {
    $data = ($jsonText -join "`n") | ConvertFrom-Json
} catch {
    Write-Host "❌ dotnet list package produced output that isn't valid JSON. Raw output:" -ForegroundColor Red
    Write-Host ($jsonText -join "`n")
    exit 1
}
$prereleaseTag = '(?i)(alpha|beta|rc|preview)'
$errors        = 0
$rows          = [System.Collections.Generic.List[string]]::new()

foreach ($project in $data.projects) {
    foreach ($framework in $project.frameworks) {
        $packages = @($framework.topLevelPackages) + @($framework.transitivePackages)
        foreach ($pkg in $packages) {
            $version = if ($pkg.resolvedVersion) { $pkg.resolvedVersion } else { $pkg.requestedVersion }
            if ($version -match $prereleaseTag) {
                Write-Host "  ❌  $($pkg.id)  $version" -ForegroundColor Red
                $rows.Add("| ❌ | ``$($pkg.id)`` | ``$version`` |")
                $errors++
            }
        }
    }
}

if ($SummaryFile) {
    if ($errors -gt 0) {
        $tableRows = $rows -join "`n"
        $md = @"
### Package Prerelease Check

| | Package | Version |
|---|---|---|
$tableRows

"@
    } else {
        $md = "### Package Prerelease Check`n`n✅ All packages are stable releases.`n`n"
    }
    Add-Content -Path $SummaryFile -Value $md -Encoding UTF8
}

if ($errors -gt 0) {
    Write-Host "`n❌ $errors prerelease package(s) found." -ForegroundColor Red
    exit 1
}

Write-Host "✅ All packages are stable releases." -ForegroundColor Green
exit 0
