<#PSScriptInfo
.VERSION 1.0.0
.GUID a4a942ec-65fe-44c7-8786-142382ffc566
.AUTHOR Felix Leistner
.COMPANYNAME Little Phoenix
.COPYRIGHT 2026 Little Phoenix
.TAGS ci cd powershell
.PROJECTURI https://github.com/LittleGitPhoenix/Automation.Workflows
#>

#Requires -Version 7
<#
.SYNOPSIS
    Returns the effective AssemblyName MSBuild property of a project.
.DESCRIPTION
    The SDK itself already defaults AssemblyName to the project file name when it isn't set explicitly, so no manual fallback is needed here.
#>
param(
    [Parameter(Mandatory)] [string] $ProjectPath
)

$ErrorActionPreference = 'Stop'

& "$PSScriptRoot/Get-ProjectProperty.ps1" -ProjectPath $ProjectPath -Property AssemblyName
