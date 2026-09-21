<#PSScriptInfo
.VERSION 1.0.0
.GUID f422c340-a5f4-4ca8-8f90-2a3c91fb7ce4
.AUTHOR Felix Leistner
.COMPANYNAME Little Phoenix
.COPYRIGHT 2026 Little Phoenix
.TAGS ci cd powershell
.PROJECTURI https://github.com/LittleGitPhoenix/Automation.Workflows
#>

#Requires -Version 7
<#
.SYNOPSIS
    Publishes one project with one named publish profile; writes the resulting archive path to stdout.
#>
param(
    [Parameter(Mandatory)] [string] $ProjectPath,
    [Parameter(Mandatory)] [string] $PublishProfile,
    [string] $WorkspaceRoot = [System.IO.Path]::GetFullPath("$PSScriptRoot/../..")
)

$ErrorActionPreference = 'Stop'

$assemblyName = & "$PSScriptRoot/Get-ProjectAssemblyName.ps1" -ProjectPath $ProjectPath

Write-Host "  Publishing '$assemblyName' with profile '$PublishProfile'..." -ForegroundColor DarkCyan

# Route dotnet output through Write-Host so the output stream stays clean.
# Callers capture this script's return value (the archive path) via $(...).
& dotnet publish $ProjectPath /p:PublishProfile="$PublishProfile" --nologo 2>&1 |
    ForEach-Object { Write-Host $_ }

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ❌ Publish failed for profile '$PublishProfile'." -ForegroundColor Red
    exit 1
}

# ── Resolve the expected archive path ─────────────────────────────────────────
# Requires the consuming repo's common.targets to define SetupPropertiesAfterPublish + CreateArchive.
$rid = & "$PSScriptRoot/Get-ProjectProperty.ps1" -ProjectPath $ProjectPath -Property RuntimeIdentifier -PublishProfile $PublishProfile

$version = (& "$PSScriptRoot/Get-ProjectVersion.ps1" -ProjectPath $ProjectPath).Version

$archivePath = Join-Path $WorkspaceRoot ".publish/$assemblyName/$assemblyName.$version.$rid.tgz"

if (-not (Test-Path $archivePath)) {
    Write-Host "  ❌ Expected archive not found: $archivePath" -ForegroundColor Red
    exit 1
}

Write-Host "  ✅ Archive: $archivePath" -ForegroundColor Green

# Only the archive path is written to the output pipeline so that callers
# can capture it cleanly: $path = & Invoke-Publish.ps1 -ProjectPath ... -PublishProfile ...
Write-Output $archivePath
