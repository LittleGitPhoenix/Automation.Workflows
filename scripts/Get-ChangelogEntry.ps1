<#PSScriptInfo
.VERSION 1.0.0
.GUID 45c6a4c8-db4a-4582-ade6-06304e9366d1
.AUTHOR Felix Leistner
.COMPANYNAME Little Phoenix
.COPYRIGHT 2026 Little Phoenix
.TAGS ci cd powershell
.PROJECTURI https://github.com/LittleGitPhoenix/Automation.Workflows
#>

#Requires -Version 7
<#
.SYNOPSIS
    Extracts the newest entry from a project's ⬙/CHANGELOG.md (Keep a Changelog format).
#>
param(
    [Parameter(Mandatory)] [string] $ProjectPath   # Path to the .csproj file.
)

$ErrorActionPreference = 'Stop'

$projectDir    = [System.IO.Path]::GetDirectoryName($ProjectPath)
$changelogPath = Join-Path $projectDir "⬙/CHANGELOG.md"

if (-not (Test-Path $changelogPath)) {
    Write-Error "CHANGELOG not found at '$changelogPath'."
    exit 1
}

$content = Get-Content -Path $changelogPath -Raw
$regex   = '(?s)(?<NEWCHANGE>(?<!#)#{2}(?!#).*?)(?=\n*_{3}|\z|(?<!#)#{2}(?!#))'

if ($content -match $regex) {
    Write-Output $Matches['NEWCHANGE'].Trim()
} else {
    Write-Error "Could not extract a changelog entry from '$changelogPath'."
    exit 1
}
