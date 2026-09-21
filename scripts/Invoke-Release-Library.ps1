<#PSScriptInfo
.VERSION 1.0.0
.GUID f82ed288-3774-4f37-8674-c3994bd66085
.AUTHOR Felix Leistner
.COMPANYNAME Little Phoenix
.COPYRIGHT 2026 Little Phoenix
.TAGS ci cd powershell
.PROJECTURI https://github.com/LittleGitPhoenix/Automation.Workflows
#>

#Requires -Version 7
<#
.SYNOPSIS
    Releases NuGet library packages: GitHub release + push to NuGet.org (CI), or local bundle (offline).
.DESCRIPTION
    In a GitHub Actions environment (GITHUB_ACTIONS = 'true'):
      - Pushes the .nupkg to NuGet.org first, since this is the only non-retryable step.
      - Creates a versioned GitHub release per project with its .nupkg as an asset; this also
        creates and pushes the git tag "{PackageId}.{Version}" remotely.
    Locally (GITHUB_ACTIONS not set):
      - Copies the already-built .nupkg into a local bundle under -LocalReleaseDir.
      - Never pushes to NuGet.org.
      - Prints which git tag would be created (-ShowTags, default on), without touching git. Pass
        -ShowTags:$false to suppress.
    In both modes, a project is skipped when its .nupkg is missing (i.e. was never built with
    GeneratePackageOnBuild). On CI, a project is also skipped once its GitHub release exists with
    the .nupkg already attached; if the release exists but is missing that asset (e.g. a prior
    run's `gh release create` failed partway through the upload), the run resumes by uploading it
    instead of creating the release again.
    Reads the "library" entry from ci-config.json's releaseTargets. With "discover: true" all
    non-test .csproj under the solution's folder are candidates; otherwise only "projects" are used.
#>
param(
    [string] $WorkspaceRoot = [System.IO.Path]::GetFullPath("$PSScriptRoot/../.."),
    [string] $ConfigPath,
    [string] $SummaryFile,
    [string] $LocalReleaseDir,
    [switch] $ShowTags = $true  # Local mode only: print which git tag would be created. Pass -ShowTags:$false to suppress.
)

$ErrorActionPreference = 'Stop'

$config       = & "$PSScriptRoot/Get-CiConfig.ps1" -WorkspaceRoot $WorkspaceRoot -ConfigPath $ConfigPath
$projectsRoot = Join-Path $WorkspaceRoot ([System.IO.Path]::GetDirectoryName($config.solutionPath))
$nugetDir     = Join-Path $WorkspaceRoot $config.nugetDir

$libraryTarget = $config.releaseTargets | Where-Object { $_.type -eq 'library' } | Select-Object -First 1
if (-not $libraryTarget) {
    Write-Host 'No "library" entry in releaseTargets - nothing to release.' -ForegroundColor DarkGray
    exit 0
}

$isGitHub = $env:GITHUB_ACTIONS -eq 'true'
$repo     = $env:GITHUB_REPOSITORY   # "owner/repo" — set automatically by GitHub Actions.

if (-not $LocalReleaseDir) {
    $LocalReleaseDir = Join-Path $WorkspaceRoot '.publish/local-release'
}
New-Item -ItemType Directory -Force -Path $LocalReleaseDir | Out-Null

$summaryRows = [System.Collections.Generic.List[string]]::new()

# ── Discover projects ─────────────────────────────────────────────────────────
if ($libraryTarget.discover) {
    $projects = Get-ChildItem -Path $projectsRoot -Recurse -Include '*.csproj' |
        Where-Object { [System.IO.Path]::GetRelativePath($projectsRoot, $_.FullName) -notmatch '(?i)(^|[/\\])Tests[/\\]' }
} else {
    $projects = @($libraryTarget.projects | ForEach-Object { Get-Item (Join-Path $WorkspaceRoot $_) })
}

# ── Per-project release loop ──────────────────────────────────────────────────
foreach ($proj in $projects) {
    $projPath      = $proj.FullName
    $version       = (& "$PSScriptRoot/Get-ProjectVersion.ps1" -ProjectPath $projPath).Version
    $packageId     = & "$PSScriptRoot/Get-ProjectPackageId.ps1" -ProjectPath $projPath
    $primaryTag    = "$packageId.$version"
    $nupkgPath     = Join-Path $nugetDir "$packageId.$version.nupkg"
    $nupkgFileName = [System.IO.Path]::GetFileName($nupkgPath)

    # A previously-pushed tag doesn't mean the release is complete: `gh release create` can leave
    # the tag and a partial release behind if it fails partway through the asset upload. Checking
    # the release's actual assets (not just tag existence) lets a retry finish an incomplete
    # release instead of skipping the project forever.
    $releaseExists = $false
    if ($isGitHub) {
        $assetsJson    = & gh release view $primaryTag --json assets --jq '.assets[].name' 2>$null
        $releaseExists = $LASTEXITCODE -eq 0
        if ($releaseExists -and $nupkgFileName -in @($assetsJson)) {
            Write-Host "⏭️  $primaryTag — release already complete, skipping." -ForegroundColor DarkGray
            continue
        }
        if ($releaseExists) {
            Write-Host "↻  $primaryTag — release exists but is missing the package asset, resuming." -ForegroundColor Yellow
        }
    }

    & "$PSScriptRoot/Write-Section.ps1" -Title "Releasing $primaryTag"

    if (-not (Test-Path $nupkgPath)) {
        Write-Host "│   ⚠️  No .nupkg found at '$nupkgPath' - was the project built first? Skipping." -ForegroundColor Yellow
        continue
    }

    $changelog = (& "$PSScriptRoot/Get-ChangelogEntry.ps1" -ProjectPath $projPath) -join "`n"

    # ── GitHub mode ───────────────────────────────────────────────────────────
    if ($isGitHub) {
        $notesFile = Join-Path $env:RUNNER_TEMP "release-notes-$packageId.md"
        $changelog | Set-Content -Path $notesFile -Encoding UTF8

        # Push to NuGet.org before tagging/releasing. --skip-duplicate makes this step safely
        # retryable, whereas tagging/releasing first would make a rerun skip the project (tag
        # already exists) before the package was ever actually pushed.
        Write-Host "│   Pushing '$packageId.$version' to NuGet.org..." -ForegroundColor Cyan
        & dotnet nuget push $nupkgPath --api-key $env:NUGET_API_KEY --source 'https://api.nuget.org/v3/index.json' --skip-duplicate
        if ($LASTEXITCODE -ne 0) {
            Write-Host '│   ❌ dotnet nuget push failed.' -ForegroundColor Red
            exit 1
        }

        if (-not $releaseExists) {
            Write-Host "│   Creating GitHub release '$primaryTag'..." -ForegroundColor Cyan
            & gh release create $primaryTag $nupkgPath --title $primaryTag --notes-file $notesFile
            if ($LASTEXITCODE -ne 0) {
                Write-Host "│   ❌ gh release create failed for '$primaryTag'." -ForegroundColor Red
                Write-Host "│   The package is already on NuGet.org, so the next run will skip the push and retry just the release." -ForegroundColor Yellow
                exit 1
            }
        } else {
            Write-Host "│   Uploading package asset to existing release '$primaryTag'..." -ForegroundColor Cyan
            & gh release upload $primaryTag $nupkgPath
            if ($LASTEXITCODE -ne 0) {
                Write-Host "│   ❌ gh release upload failed for '$primaryTag'." -ForegroundColor Red
                exit 1
            }
        }

        $releaseUrl = "https://github.com/$repo/releases/tag/$primaryTag"
        $summaryRows.Add("| [``$primaryTag``]($releaseUrl) | ``$version`` | ``$packageId`` |")

    # ── Local mode ────────────────────────────────────────────────────────────
    } else {
        $bundleDir = Join-Path $LocalReleaseDir $primaryTag
        New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null
        Copy-Item $nupkgPath -Destination $bundleDir
        $changelog | Set-Content -Path (Join-Path $bundleDir 'release-notes.md') -Encoding UTF8

        Write-Host "└── ✅ Local bundle: $bundleDir" -ForegroundColor Green
        $summaryRows.Add("| ``$primaryTag`` | ``$version`` | ``$packageId`` |")

        if ($ShowTags) {
            Write-Host "  📌 Would tag: $primaryTag" -ForegroundColor Yellow
        }
    }
}

# ── Post-loop: finalize ───────────────────────────────────────────────────────
if ($summaryRows.Count -eq 0) {
    Write-Host "`nNo new package versions — nothing to release." -ForegroundColor DarkGray
    if ($SummaryFile) {
        Add-Content -Path $SummaryFile -Value "### Releases`n`n_No new releases were created._`n" -Encoding UTF8
    }
    exit 0
}

if ($SummaryFile) {
    $tableRows = $summaryRows -join "`n"
    $md = @"
### Releases

| Release | Version | Package |
|---|---|---|
$tableRows

"@
    Add-Content -Path $SummaryFile -Value $md -Encoding UTF8
}

Write-Host "`n✅ Library release step complete." -ForegroundColor Green
exit 0
