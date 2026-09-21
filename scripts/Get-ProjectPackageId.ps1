<#PSScriptInfo
.VERSION 1.0.0
.GUID 3ceb4350-fbfc-4a0c-b280-a5dec3e3350e
.AUTHOR Felix Leistner
.COMPANYNAME Little Phoenix
.COPYRIGHT 2026 Little Phoenix
.TAGS ci cd powershell
.PROJECTURI https://github.com/LittleGitPhoenix/Automation.Workflows
#>

#Requires -Version 7
<#
.SYNOPSIS
    Returns the effective PackageId MSBuild property of a project.
.DESCRIPTION
    The SDK itself already defaults PackageId to AssemblyName when it isn't set explicitly, so
    no manual fallback is needed here.
#>
param(
    [Parameter(Mandatory)] [string] $ProjectPath
)

$ErrorActionPreference = 'Stop'

& "$PSScriptRoot/Get-ProjectProperty.ps1" -ProjectPath $ProjectPath -Property PackageId
