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
      - Creates a versioned GitHub release per project with its .nupkg as an asset.
      - Pushes the .nupkg to NuGet.org.
      - Creates a git tag "{PackageId}.{Version}" and pushes it.
    Locally (GITHUB_ACTIONS not set):
      - Copies the already-built .nupkg into a local bundle under -LocalReleaseDir.
      - Never pushes to NuGet.org.
      - Optionally creates a local git tag (-CreateTags).
    In both modes, a project is skipped when its .nupkg is missing (i.e. was never built with
    GeneratePackageOnBuild) or - on CI only - when its version tag already exists.
    Reads the "library" entry from ci-config.json's releaseTargets. With "discover: true" all
    non-test .csproj under the solution's folder are candidates; otherwise only "projects" are used.
#>
param(
    [string] $WorkspaceRoot = [System.IO.Path]::GetFullPath("$PSScriptRoot/../.."),
    [string] $ConfigPath,
    [string] $SummaryFile,
    [string] $LocalReleaseDir
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
$stagedTags  = [System.Collections.Generic.List[string]]::new()

# ── Discover projects ─────────────────────────────────────────────────────────
if ($libraryTarget.discover) {
    $projects = Get-ChildItem -Path $projectsRoot -Recurse -Include '*.csproj' |
        Where-Object { [System.IO.Path]::GetRelativePath($projectsRoot, $_.FullName) -notmatch '(?i)(^|[/\\])Tests[/\\]' }
} else {
    $projects = @($libraryTarget.projects | ForEach-Object { Get-Item (Join-Path $WorkspaceRoot $_) })
}

# ── Per-project release loop ──────────────────────────────────────────────────
foreach ($proj in $projects) {
    $projPath   = $proj.FullName
    $version    = (& "$PSScriptRoot/Get-ProjectVersion.ps1" -ProjectPath $projPath).Version
    $packageId  = & "$PSScriptRoot/Get-ProjectPackageId.ps1" -ProjectPath $projPath
    $primaryTag = "$packageId.$version"

    if ($isGitHub) {
        $tagCheck = & git tag -l $primaryTag
        if ($tagCheck) {
            Write-Host "⏭️  $primaryTag — already tagged, skipping." -ForegroundColor DarkGray
            continue
        }
    }

    & "$PSScriptRoot/Write-Section.ps1" -Title "Releasing $primaryTag"

    $nupkgPath = Join-Path $nugetDir "$packageId.$version.nupkg"
    if (-not (Test-Path $nupkgPath)) {
        Write-Host "│   ⚠️  No .nupkg found at '$nupkgPath' - was the project built first? Skipping." -ForegroundColor Yellow
        continue
    }

    $changelog = (& "$PSScriptRoot/Get-ChangelogEntry.ps1" -ProjectPath $projPath) -join "`n"

    # ── GitHub mode ───────────────────────────────────────────────────────────
    if ($isGitHub) {
        $notesFile = Join-Path $env:RUNNER_TEMP "release-notes-$packageId.md"
        $changelog | Set-Content -Path $notesFile -Encoding UTF8

        Write-Host "│   Creating GitHub release '$primaryTag'..." -ForegroundColor Cyan
        & gh release create $primaryTag $nupkgPath --title $primaryTag --notes-file $notesFile
        if ($LASTEXITCODE -ne 0) {
            Write-Host "│   ❌ gh release create failed for '$primaryTag'." -ForegroundColor Red
            # A previous run may have been cancelled/interrupted after creating the release but before tagging/pushing.
            Write-Host "│   If '$primaryTag' already exists on GitHub from an earlier interrupted run, delete it (and its tag, if orphaned) and re-run:" -ForegroundColor Yellow
            Write-Host "│     gh release delete $primaryTag --yes" -ForegroundColor Yellow
            Write-Host "│     git push origin :refs/tags/$primaryTag" -ForegroundColor Yellow
            exit 1
        }

        Write-Host "│   Pushing '$packageId.$version' to NuGet.org..." -ForegroundColor Cyan
        & dotnet nuget push $nupkgPath --api-key $env:NUGET_API_KEY --source 'https://api.nuget.org/v3/index.json' --skip-duplicate
        if ($LASTEXITCODE -ne 0) {
            Write-Host '│   ❌ dotnet nuget push failed.' -ForegroundColor Red
            exit 1
        }

        & git tag $primaryTag
        if ($LASTEXITCODE -ne 0) {
            Write-Host "│   ❌ git tag '$primaryTag' failed (exit code $LASTEXITCODE)." -ForegroundColor Red
            exit 1
        }
        $stagedTags.Add($primaryTag)
        Write-Host "│   📌 Staged tag: $primaryTag" -ForegroundColor DarkGray

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

if ($isGitHub -and $stagedTags.Count -gt 0) {
    & git push origin --tags
    if ($LASTEXITCODE -ne 0) {
        Write-Host '❌ git push --tags failed.' -ForegroundColor Red
        exit 1
    }
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
