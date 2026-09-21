<#PSScriptInfo
.VERSION 1.0.0
.GUID ff333dcd-0b66-43be-a54f-47a4795be05b
.AUTHOR Felix Leistner
.COMPANYNAME Little Phoenix
.COPYRIGHT 2026 Little Phoenix
.TAGS ci cd powershell
.PROJECTURI https://github.com/LittleGitPhoenix/Automation.Workflows
#>

#Requires -Version 7
<#
.SYNOPSIS
    Base local CI runner, shared by every consuming repository via a thin per-repo wrapper.
.DESCRIPTION
    Chains the individual CI scripts to replicate what the reusable GitHub Actions workflows do.
    Steps that are GitHub-only are skipped and clearly noted. Run without -Mode for an interactive menu.
    Consuming repos should not call this script directly - instead add a thin wrapper at
    .github/scripts/Invoke-CI.ps1 that resolves this script via the
    PHOENIX_REUSABLE_WORKFLOWS_REPOSITORY_PATH environment variable and forwards -WorkspaceRoot.
.EXAMPLE
    .\Invoke-CI.ps1 -WorkspaceRoot D:\GIT\Phoenix\Functionality.Logging.Extensions -Mode Validate
#>
param(
    [Parameter(Mandatory)] [string] $WorkspaceRoot,
    [string] $ConfigPath,
    [ValidateSet('Validate', 'Release', 'All')]
    [string] $Mode,
    [switch] $CreateTags        # Pre-answer the "create git tags?" prompt with Yes.
)

$ErrorActionPreference = 'Stop'

# ── Interactive mode selection ─────────────────────────────────────────────────
if (-not $Mode) {
    Write-Host ''
    Write-Host '╔════════════════════════════════════╗' -ForegroundColor Cyan
    Write-Host '║         Phoenix — Local CI          ║' -ForegroundColor Cyan
    Write-Host '╚════════════════════════════════════╝' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  [1]  Validate  — version checks, build, tests'
    Write-Host '  [2]  Release   — validate + local release bundle'
    Write-Host ''
    $choice = Read-Host 'Select [1/2]'
    $Mode = switch ($choice) {
        '1'     { 'Validate' }
        '2'     { 'Release'  }
        default { Write-Host 'Unknown choice — defaulting to Validate.' -ForegroundColor Yellow; 'Validate' }
    }
}

if ($Mode -in @('Release', 'All') -and -not $CreateTags) {
    $answer     = Read-Host 'Create local git tags? [y/N]'
    $CreateTags = $answer -match '^[Yy]$'
}

# ── Output directory & summary file ───────────────────────────────────────────
$timestamp       = Get-Date -Format 'yyyyMMdd-HHmmss'
$localReleaseDir = Join-Path $WorkspaceRoot ".publish/local-release/$timestamp"
$summaryFile     = Join-Path $localReleaseDir 'local-ci-summary.md'
New-Item -ItemType Directory -Force -Path $localReleaseDir | Out-Null

function Invoke-Script {
    param([string] $Name, [hashtable] $Extra = @{})
    $path   = Join-Path $PSScriptRoot $Name
    $params = @{ WorkspaceRoot = $WorkspaceRoot; ConfigPath = $ConfigPath } + $Extra
    $global:LASTEXITCODE = 0
    & $path @params
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n❌ '$Name' exited with code $LASTEXITCODE." -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

# ── Phase 1: Validate ─────────────────────────────────────────────────────────
Write-Host "`n[1/5] Project version check" -ForegroundColor Cyan
Invoke-Script 'Test-ProjectVersions.ps1' @{ SummaryFile = $summaryFile }

Write-Host "`n[2/5] Prerelease package check" -ForegroundColor Cyan
Invoke-Script 'Test-PackageVersions.ps1' @{ SummaryFile = $summaryFile }

Write-Host "`n[3/5] Changelog version check" -ForegroundColor Cyan
Invoke-Script 'Test-ChangelogVersions.ps1' @{ SummaryFile = $summaryFile }

Write-Host "`n[4/5] Build" -ForegroundColor Cyan
Invoke-Script 'Invoke-Build.ps1'

Write-Host "`n[5/5] Tests + coverage" -ForegroundColor Cyan
Invoke-Script 'Invoke-Tests.ps1' @{ SummaryFile = $summaryFile }

Write-Host ''
Write-Host '[GITHUB-ONLY] Test results would be published as a PR check via dorny/test-reporter.' -ForegroundColor DarkGray

# ── Phase 2: Release ──────────────────────────────────────────────────────────
if ($Mode -in @('Release', 'All')) {
    $config         = & "$PSScriptRoot/Get-CiConfig.ps1" -WorkspaceRoot $WorkspaceRoot -ConfigPath $ConfigPath
    $releaseTargets = @($config.releaseTargets)

    if ($releaseTargets.Count -eq 0) {
        Write-Host "`n[Release] ci-config.json declares no releaseTargets - nothing to release." -ForegroundColor Yellow
    }

    foreach ($target in $releaseTargets) {
        $releaseExtra = @{ SummaryFile = $summaryFile; LocalReleaseDir = $localReleaseDir }

        switch ($target.type) {
            'library' {
                Write-Host "`n[Release] Creating local library release bundle..." -ForegroundColor Cyan
                Invoke-Script 'Invoke-Release-Library.ps1' $releaseExtra
                Write-Host '[GITHUB-ONLY] GitHub releases + NuGet.org push would happen via gh + dotnet nuget push.' -ForegroundColor DarkGray
            }
            'executable' {
                if ($CreateTags) { $releaseExtra['CreateTags'] = $true }
                Write-Host "`n[Release] Creating local executable release bundle..." -ForegroundColor Cyan
                Invoke-Script 'Invoke-Release-Executable.ps1' $releaseExtra
                Write-Host '[GITHUB-ONLY] GitHub releases would be created via gh release create.' -ForegroundColor DarkGray
                if (-not $CreateTags) {
                    Write-Host '[GITHUB-ONLY] Git tags would be pushed to origin.' -ForegroundColor DarkGray
                }
            }
            default {
                Write-Host "⚠️  Unknown releaseTargets type '$($target.type)' - skipping." -ForegroundColor Yellow
            }
        }
    }
}

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host "`n✅ Local CI run complete." -ForegroundColor Green
if (Test-Path $summaryFile) {
    Write-Host "Summary written to: $summaryFile" -ForegroundColor DarkGray
}
[Console]::ResetColor()
