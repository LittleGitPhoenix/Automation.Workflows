#Requires -Version 7
<#
.SYNOPSIS
    Manually runs the Pester test suite for the scripts in this repository.
.DESCRIPTION
    Not part of any CI workflow. This is a local developer tool that verifies scripts/*.ps1 behavior
    against the fixtures under tests/Fixtures. Requires a local .NET SDK, since the
    property-extraction script tests shell out to `dotnet msbuild`.
#>
param(
    [string] $Path = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$pester = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version] '6.0.0' } | Select-Object -First 1
if (-not $pester) {
    Write-Host 'Pester 6+ not found, installing for the current user...' -ForegroundColor Cyan
    Install-Module Pester -MinimumVersion 6.0 -Scope CurrentUser -Force -SkipPublisherCheck
}

Import-Module Pester -MinimumVersion 6.0

$result = Invoke-Pester -Path $Path -Output Detailed -PassThru
exit $result.FailedCount
