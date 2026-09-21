<#PSScriptInfo
.VERSION 1.0.0
.GUID cc3f7804-c22a-4db4-96eb-8b68aa7a25be
.AUTHOR Felix Leistner
.COMPANYNAME Little Phoenix
.COPYRIGHT 2026 Little Phoenix
.TAGS ci cd powershell
.PROJECTURI https://github.com/LittleGitPhoenix/Automation.Workflows
#>

#Requires -Version 7
<#
.SYNOPSIS
    Returns all relevant defined (== not empty) version MSBuild properties of a project.
#>
param(
    [Parameter(Mandatory)] [string] $ProjectPath
)

$ErrorActionPreference = 'Stop'

$versionProperties = @(
    'AssemblyVersion'
    'FileVersion'
    'InformationalVersion'
    'PackageVersion'
    'Version'
)

$msbuildArgs = @($ProjectPath, '-nologo', "-getProperty:$($versionProperties -join ',')")
$rawOutput = & dotnet msbuild @msbuildArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "dotnet msbuild failed to evaluate version properties on '$ProjectPath'."
    exit 1
}

try {
    $result = ($rawOutput -join "`n") | ConvertFrom-Json
} catch {
    Write-Error "dotnet msbuild -getProperty did not return valid JSON for '$ProjectPath'. Raw output:`n$($rawOutput -join "`n")"
    exit 1
}

$versions = [ordered]@{}
foreach ($property in $versionProperties) {
    $value = $result.Properties.$property
    if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
        $versions[$property] = $value
    }
}

Write-Output ([pscustomobject]$versions)
