<#PSScriptInfo
.VERSION 1.0.0
.GUID 78f0585b-c7d1-4b75-92ad-c00c546e8064
.AUTHOR Felix Leistner
.COMPANYNAME Little Phoenix
.COPYRIGHT 2026 Little Phoenix
.TAGS ci cd powershell
.PROJECTURI https://github.com/LittleGitPhoenix/Automation.Workflows
#>

#Requires -Version 7
<#
.SYNOPSIS
    Writes a framed section heading to the console.
.EXAMPLE
    & "$PSScriptRoot/Write-Section.ps1" -Title "Releasing Phoenix.Functionality.Logging.Base.1.0.0"
#>
param(
    [Parameter(Mandatory)] [string] $Title,
    [string] $ForegroundColor = 'Cyan'
)

$inner  = " $Title "
$line   = '═' * $inner.Length
$top    = "╔$line╗"
$middle = "║$inner║"
$bottom = "╚$line╝"

Write-Host ''
Write-Host $top    -ForegroundColor $ForegroundColor
Write-Host $middle -ForegroundColor $ForegroundColor
Write-Host $bottom -ForegroundColor $ForegroundColor
