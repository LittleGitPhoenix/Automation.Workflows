<#PSScriptInfo
.VERSION 1.0.0
.GUID 5372f174-4804-44b6-9020-56d1dd4d510a
.AUTHOR Felix Leistner
.COMPANYNAME Little Phoenix
.COPYRIGHT 2026 Little Phoenix
.TAGS ci cd powershell
.PROJECTURI https://github.com/LittleGitPhoenix/Automation.Workflows
#>

#Requires -Version 7
<#
.SYNOPSIS
    Evaluates one or more MSBuild properties of a project via `dotnet msbuild -getProperty`.
.DESCRIPTION
    Unlike scanning the .csproj file's raw text, this asks MSBuild itself to evaluate the property,
	so it correctly resolves values inherited from Directory.Build.props, set by Condition-guarded PropertyGroups, or defined via any other import.
.EXAMPLE
    & "$PSScriptRoot/Get-ProjectProperty.ps1" -ProjectPath $projPath -Property Version
.EXAMPLE
    & "$PSScriptRoot/Get-ProjectProperty.ps1" -ProjectPath $projPath -Property Version, PackageId, AssemblyName
.EXAMPLE
    & "$PSScriptRoot/Get-ProjectProperty.ps1" -ProjectPath $projPath -Property RuntimeIdentifier -PublishProfile 'linux-x64'
#>
param(
    [Parameter(Mandatory)] [string]   $ProjectPath,
    [Parameter(Mandatory)] [string[]] $Property,
    [string] $PublishProfile
)

$ErrorActionPreference = 'Stop'

$msbuildArgs = @($ProjectPath, '-nologo', "-getProperty:$($Property -join ',')")
if ($PublishProfile) {
    $msbuildArgs += "/p:PublishProfile=$PublishProfile"
}

$rawOutput = & dotnet msbuild @msbuildArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "dotnet msbuild failed to evaluate propert$(if ($Property.Count -gt 1) { 'ies' } else { 'y' }) '$($Property -join ', ')' on '$ProjectPath'."
    exit 1
}

# With a single property, -getProperty prints the bare value instead of a JSON object.
if ($Property.Count -eq 1) {
    $value = ($rawOutput -join "`n").Trim()
    if ([string]::IsNullOrEmpty($value)) {
        Write-Error "Property '$($Property[0])' evaluated to an empty value on '$ProjectPath'."
        exit 1
    }
    # Return instead of exiting, since this script is also invoked in-process (via `&`) by callers that must keep running afterwards.
    Write-Output $value
    return
}

try {
    $result = ($rawOutput -join "`n") | ConvertFrom-Json
} catch {
    Write-Error "dotnet msbuild -getProperty did not return valid JSON for '$ProjectPath'. Raw output:`n$($rawOutput -join "`n")"
    exit 1
}

$output = [ordered] @{}
foreach ($name in $Property) {
    $value = $result.Properties.$name
    if ($null -eq $value -or $value -eq '') {
        Write-Error "Property '$name' evaluated to an empty value on '$ProjectPath'."
        exit 1
    }
    $output[$name] = $value
}

Write-Output ([pscustomobject] $output)
