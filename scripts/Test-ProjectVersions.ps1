<#PSScriptInfo
.VERSION 1.0.0
.GUID 5c28b8fa-80cb-4626-8bda-53b527af0f0e
.AUTHOR Felix Leistner
.COMPANYNAME Little Phoenix
.COPYRIGHT 2026 Little Phoenix
.TAGS ci cd powershell
.PROJECTURI https://github.com/LittleGitPhoenix/Automation.Workflows
#>

#Requires -Version 7
<#
.SYNOPSIS
    Verifies all non-test .csproj/.vbproj/.fsproj files under a repo carry a valid SemVer <Version>.
    Allows X.Y.Z or X.Y.Z-RC.N (no alpha/beta/preview).
#>
param(
    [string] $WorkspaceRoot = [System.IO.Path]::GetFullPath("$PSScriptRoot/../.."),
    [string] $ConfigPath,
    [string] $SummaryFile
)

$ErrorActionPreference = 'Stop'

$config       = & "$PSScriptRoot/Get-CiConfig.ps1" -WorkspaceRoot $WorkspaceRoot -ConfigPath $ConfigPath
$projectsRoot = Join-Path $WorkspaceRoot ([System.IO.Path]::GetDirectoryName($config.solutionPath))

Write-Host 'Checking project versions...' -ForegroundColor Cyan

$semverRegex = '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-RC\.(0|[1-9][0-9]*))?$'
$errors      = 0
$rows        = [System.Collections.Generic.List[string]]::new()

$projectFiles = Get-ChildItem -Path $projectsRoot -Recurse -Include '*.csproj', '*.vbproj', '*.fsproj' |
    Where-Object { [System.IO.Path]::GetRelativePath($projectsRoot, $_.FullName) -notmatch '(?i)(^|[/\\])Tests[/\\]' }

foreach ($file in $projectFiles) {
    $versions = $null
    try {
        $versions = & "$PSScriptRoot/Get-ProjectVersion.ps1" -ProjectPath $file.FullName 2>$null
    } catch {
        $versions = $null
    }

    if (-not $versions -or $LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$versions.Version)) {
        Write-Host "  ❌  $($file.Name)  →  version property evaluation failed" -ForegroundColor Red
        $rows.Add("| ❌ | ``$($file.Name)`` | — | Version property evaluation failed |")
        $errors++
        continue
    }

    foreach ($version in $versions.PSObject.Properties) {
        $property = $version.Name
        $ver      = $version.Value
        if ($ver -match $semverRegex) {
            Write-Host "  ✅  $($file.Name)  →  $property = $ver" -ForegroundColor Green
            $rows.Add("| ✅ | ``$($file.Name)`` | ``$property = $ver`` | Valid SemVer |")
        } else {
            Write-Host "  ❌  $($file.Name)  →  $property = '$ver' is not valid SemVer" -ForegroundColor Red
            $rows.Add("| ❌ | ``$($file.Name)`` | ``$property = $ver`` | Not SemVer X.Y.Z(-RC.N) |")
            $errors++
        }
    }
}

if ($SummaryFile) {
    $tableRows = $rows -join "`n"
    $md = @"
### Project Version Check

| | Project | Version | Status |
|---|---|---|---|
$tableRows

"@
    Add-Content -Path $SummaryFile -Value $md -Encoding UTF8
}

if ($errors -gt 0) {
    Write-Host "`n❌ $errors project version error(s)." -ForegroundColor Red
    exit 1
}

Write-Host "`n✅ All project versions are valid SemVer." -ForegroundColor Green
exit 0
