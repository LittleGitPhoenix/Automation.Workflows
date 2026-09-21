<#PSScriptInfo
.VERSION 1.0.0
.GUID e6d1b5f8-c17b-479d-b04d-7058c3636c87
.AUTHOR Felix Leistner
.COMPANYNAME Little Phoenix
.COPYRIGHT 2026 Little Phoenix
.TAGS ci cd powershell
.PROJECTURI https://github.com/LittleGitPhoenix/Automation.Workflows
#>

#Requires -Version 7
<#
.SYNOPSIS
    Loads and validates a consumer repository's .github/ci-config.json.
.DESCRIPTION
    ci-config.json shape:
    {
      "solutionPath":     "src/Foo.sln",           // required, relative to the repo root
      "coverageScope":    "[Foo.*]*",              // required, coverlet --coverlet-include pattern
      "coverageExclude":  "[*.Test]*",             // optional, coverlet --coverlet-exclude pattern
      "nugetDir":         ".nuget",                // optional, default ".nuget". Where built .nupkg files land.
      "releaseTargets": [                          // optional, required for Release mode
        { "type": "library",    "discover": true },
        { "type": "executable", "projects": [ "src/Foo/Foo.csproj" ], "publishProfilesDir": "Properties/PublishProfiles" }
      ]
    }
#>
param(
    [Parameter(Mandatory)] [string] $WorkspaceRoot,
    [string] $ConfigPath
)

$ErrorActionPreference = 'Stop'

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $WorkspaceRoot '.github/ci-config.json'
}

if (-not (Test-Path $ConfigPath -PathType Leaf)) {
    Write-Error "ci-config.json not found at '$ConfigPath'."
    exit 1
}

$config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

if (-not $config.solutionPath) {
    Write-Error "ci-config.json is missing required property 'solutionPath'."
    exit 1
}

$resolvedSolutionPath = Join-Path $WorkspaceRoot $config.solutionPath
if (-not (Test-Path $resolvedSolutionPath -PathType Leaf)) {
    Write-Error "ci-config.json's 'solutionPath' does not resolve to an existing file: '$resolvedSolutionPath'."
    exit 1
}

if (-not $config.coverageScope) {
    Write-Error "ci-config.json is missing required property 'coverageScope'."
    exit 1
}

if (-not $config.nugetDir) {
    $config | Add-Member -NotePropertyName 'nugetDir' -NotePropertyValue '.nuget' -Force
}

if ($config.releaseTargets) {
    $releaseTargets = @($config.releaseTargets)
    if ($releaseTargets -isnot [array] -and $config.releaseTargets -isnot [System.Collections.IEnumerable]) {
        Write-Error "ci-config.json's 'releaseTargets' must be an array."
        exit 1
    }

    $knownTypes  = @('library', 'executable')
    $seenTypes   = @{}
    foreach ($target in $releaseTargets) {
        if ($knownTypes -notcontains $target.type) {
            Write-Error "ci-config.json has a 'releaseTargets' entry with an unknown type: '$($target.type)'. Known types: $($knownTypes -join ', ')."
            exit 1
        }
        if ($seenTypes.ContainsKey($target.type)) {
            Write-Error "ci-config.json's 'releaseTargets' must contain at most one entry per type. Found more than one '$($target.type)' entry."
            exit 1
        }
        $seenTypes[$target.type] = $true

        if ($target.type -eq 'library') {
            if (-not $target.discover -and (-not $target.projects -or $target.projects.Count -eq 0)) {
                Write-Error "ci-config.json's 'library' releaseTargets entry must set 'discover: true' or declare a non-empty 'projects' list."
                exit 1
            }
        }
        if ($target.type -eq 'executable') {
            if (-not $target.projects -or $target.projects.Count -eq 0) {
                Write-Error "ci-config.json's 'executable' releaseTargets entry must declare a non-empty 'projects' list."
                exit 1
            }
        }
    }
}

Write-Output $config
