<#PSScriptInfo
.VERSION 1.0.0
.GUID 75e13c4a-f590-471e-bc5c-c1859f6ff92f
.AUTHOR Felix Leistner
.COMPANYNAME Little Phoenix
.COPYRIGHT 2026 Little Phoenix
.TAGS ci cd powershell
.PROJECTURI https://github.com/LittleGitPhoenix/Automation.Workflows
#>

#Requires -Version 7
param(
    [string] $WorkspaceRoot = [System.IO.Path]::GetFullPath("$PSScriptRoot/../.."),
    [string] $ConfigPath,
    [string] $Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'

$config      = & "$PSScriptRoot/Get-CiConfig.ps1" -WorkspaceRoot $WorkspaceRoot -ConfigPath $ConfigPath
$toolManifest = Join-Path $WorkspaceRoot '.config/dotnet-tools.json'

if (Test-Path $toolManifest) {
    Write-Host 'Restoring local dotnet tools...' -ForegroundColor Cyan
    & dotnet tool restore --tool-manifest $toolManifest --no-cache
    if ($LASTEXITCODE -ne 0) {
        Write-Host '❌ Tool restore failed.' -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host 'No .config/dotnet-tools.json manifest found - skipping tool restore.' -ForegroundColor DarkGray
}

$sln = Join-Path $WorkspaceRoot $config.solutionPath
Write-Host "Building '$sln' ($Configuration)..." -ForegroundColor Cyan

& dotnet build $sln -c $Configuration --nologo

if ($LASTEXITCODE -ne 0) {
    Write-Host '❌ Build failed.' -ForegroundColor Red
    exit 1
}

Write-Host '✅ Build succeeded.' -ForegroundColor Green
exit 0
