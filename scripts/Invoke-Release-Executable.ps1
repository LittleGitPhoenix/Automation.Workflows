<#PSScriptInfo
.VERSION 1.0.0
.GUID 7f5dbc06-d8d8-43db-a51e-261839f0f42e
.AUTHOR Felix Leistner
.COMPANYNAME Little Phoenix
.COPYRIGHT 2026 Little Phoenix
.TAGS ci cd powershell
.PROJECTURI https://github.com/LittleGitPhoenix/Automation.Workflows
#>

#Requires -Version 7
<#
.SYNOPSIS
    Publishes self-contained executables and creates releases.
.DESCRIPTION
    In a GitHub Actions environment (GITHUB_ACTIONS = 'true'):
      - Creates RID-specific git tags (AssemblyName.Version.RID) and pushes them first, since tag
        creation is idempotent and retryable, unlike the release step below.
      - Creates a versioned GitHub release per project with all RID archives as assets; this also
        creates and pushes the primary "AssemblyName.Version" git tag remotely.
      - Optionally updates an auto-updater index release (updater.json) if the "executable"
        releaseTargets entry in ci-config.json declares an "updaterReleaseName".
    Locally (GITHUB_ACTIONS not set):
      - Publishes projects and creates per-project .zip-equivalent bundles under
        -LocalReleaseDir (defaults to .publish/local-release/).
      - Writes a local updater.json mirror only if "updaterReleaseName" is configured.
      - Prints which git tags would be created (-ShowTags, default on), without touching git. Pass
        -ShowTags:$false to suppress.
    In both modes, a project is skipped (CI only) once its GitHub release exists with all expected
    RID assets attached; if the release exists but is missing assets (e.g. a prior run's
    `gh release create` failed partway through uploads), the run resumes by uploading just the
    missing ones instead of creating the release again. Even when a project's release is already
    complete and nothing is published for it, its updater entry is still recomputed so a rerun can
    repair a previously failed/missed updater index update independently of new releases.
    Requires the consuming repo's own common.targets to define SetupPropertiesAfterPublish +
    CreateArchive (this is app build-system logic, not something this script provides), plus a
    Properties/PublishProfiles/*.pubxml per RID. Profiles with "local only" in the name are skipped.
    Reads the "executable" entry from ci-config.json's releaseTargets:
      { "type": "executable", "projects": [ "src/Foo/Foo.csproj" ], "publishProfilesDir": "Properties/PublishProfiles", "updaterReleaseName": "Foo-Updater" }
#>
param(
    [string] $WorkspaceRoot = [System.IO.Path]::GetFullPath("$PSScriptRoot/../.."),
    [string] $ConfigPath,
    [string] $SummaryFile,
    [string] $LocalReleaseDir,
    [switch] $ShowTags = $true  # Local mode only: print which git tags would be created. Pass -ShowTags:$false to suppress.
)

$ErrorActionPreference = 'Stop'

# ── Helper: update an optional auto-updater index release on GitHub ──────────
function Update-UpdaterRelease {
    param(
        [hashtable] $Projects,
        [string]    $Repo,
        [string]    $UpdaterTag
    )

    $tempDir  = $env:RUNNER_TEMP
    $jsonPath = Join-Path $tempDir 'updater.json'

    & gh release view $UpdaterTag | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Creating '$UpdaterTag' index release..." -ForegroundColor Cyan
        [ordered] @{ generated = ''; projects = [ordered] @{} } |
            ConvertTo-Json -Depth 5 |
            Set-Content -Path $jsonPath -Encoding UTF8
        & gh release create $UpdaterTag $jsonPath `
            --title    $UpdaterTag `
            --notes    'Index release used by the auto-updater. Do not delete or modify manually.' `
            --prerelease
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Failed to create '$UpdaterTag' index release." -ForegroundColor Red
            exit 1
        }
    } else {
        & gh release download $UpdaterTag --pattern 'updater.json' --dir $tempDir --clobber
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $jsonPath)) {
            Write-Host "❌ Failed to download existing 'updater.json' asset from release '$UpdaterTag'." -ForegroundColor Red
            exit 1
        }
    }

    $data = Get-Content $jsonPath -Raw | ConvertFrom-Json -AsHashtable
    if (-not $data.projects) { $data.projects = @{} }
    foreach ($key in $Projects.Keys) { $data.projects[$key] = $Projects[$key] }
    $data.generated = (Get-Date -Format 'o')
    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8

    # --clobber replaces an existing asset with the same name.
    & gh release upload $UpdaterTag $jsonPath --clobber
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to update '$UpdaterTag'." -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ '$UpdaterTag' release updated." -ForegroundColor Green
}

# ── Setup ─────────────────────────────────────────────────────────────────────
$config = & "$PSScriptRoot/Get-CiConfig.ps1" -WorkspaceRoot $WorkspaceRoot -ConfigPath $ConfigPath

$executableTarget = $config.releaseTargets | Where-Object { $_.type -eq 'executable' } | Select-Object -First 1
if (-not $executableTarget) {
    Write-Host 'No "executable" entry in releaseTargets - nothing to release.' -ForegroundColor DarkGray
    exit 0
}
# Get-CiConfig.ps1 already validated that an "executable" entry declares a non-empty "projects" list.

$isGitHub = $env:GITHUB_ACTIONS -eq 'true'
$repo     = $env:GITHUB_REPOSITORY   # "owner/repo" — set automatically by GitHub Actions.

if (-not $LocalReleaseDir) {
    $LocalReleaseDir = Join-Path $WorkspaceRoot '.publish/local-release'
}
New-Item -ItemType Directory -Force -Path $LocalReleaseDir | Out-Null

# Accumulate per-project data for a single updater-index write at the end (only if configured).
$updaterProjects = [ordered] @{}
$summaryRows     = [System.Collections.Generic.List[string]]::new()

$projects = @($executableTarget.projects | ForEach-Object { Get-Item (Join-Path $WorkspaceRoot $_) })

# ── Per-project release loop ──────────────────────────────────────────────────
foreach ($proj in $projects) {
    $projPath     = $proj.FullName
    $projDir      = [System.IO.Path]::GetDirectoryName($projPath)
    $assemblyName = & "$PSScriptRoot/Get-ProjectAssemblyName.ps1" -ProjectPath $projPath

    $version    = (& "$PSScriptRoot/Get-ProjectVersion.ps1" -ProjectPath $projPath).Version
    $primaryTag = "$assemblyName.$version"

    $profilesDirName = if ($executableTarget.publishProfilesDir) { $executableTarget.publishProfilesDir } else { 'Properties/PublishProfiles' }
    $profilesDir     = Join-Path $projDir $profilesDirName
    $profiles        = Get-ChildItem -Path $profilesDir -Filter '*.pubxml' |
        Where-Object { $_.BaseName -notlike '*local only*' }

    if ($profiles.Count -eq 0) {
        Write-Host "⏭️  $primaryTag — no eligible publish profiles, skipping." -ForegroundColor Yellow
        continue
    }

    # A previously-pushed tag doesn't mean the release is complete: `gh release create` can leave
    # the tag and a partial release behind if it fails partway through asset uploads. Checking the
    # release's actual assets (not just tag existence) lets a retry finish an incomplete release
    # instead of skipping the project forever.
    $releaseExists  = $false
    $existingAssets = @()
    if ($isGitHub) {
        $expectedFiles = [ordered] @{}
        foreach ($pubProfile in $profiles) {
            $rid = & "$PSScriptRoot/Get-ProjectProperty.ps1" -ProjectPath $projPath -Property RuntimeIdentifier -PublishProfile $pubProfile.BaseName
            $expectedFiles[$rid] = "$assemblyName.$version.$rid.tgz"
        }

        $assetsJson    = & gh release view $primaryTag --json assets --jq '.assets[].name' 2>$null
        $releaseExists = $LASTEXITCODE -eq 0
        if ($releaseExists) {
            $existingAssets = @($assetsJson)
            $missingFiles   = @($expectedFiles.Values | Where-Object { $_ -notin $existingAssets })
            if ($missingFiles.Count -eq 0) {
                Write-Host "⏭️  $primaryTag — release already complete, skipping." -ForegroundColor DarkGray
                # Recompute the updater entry even though nothing is published here, so a rerun can
                # still repair a previously failed/missed Update-UpdaterRelease call for this project.
                if ($executableTarget.updaterReleaseName) {
                    $changelog = (& "$PSScriptRoot/Get-ChangelogEntry.ps1" -ProjectPath $projPath) -join "`n"
                    $assetUrls = [ordered] @{}
                    foreach ($rid in $expectedFiles.Keys) {
                        $assetUrls[$rid] = "https://github.com/$repo/releases/download/$primaryTag/$($expectedFiles[$rid])"
                    }
                    $updaterProjects[$assemblyName] = [ordered] @{
                        version   = $version
                        release   = $primaryTag
                        changelog = $changelog
                        assets    = $assetUrls
                    }
                }
                continue
            }
            Write-Host "↻  $primaryTag — release exists but is missing $($missingFiles.Count) asset(s), resuming." -ForegroundColor Yellow
        }
    }

    & "$PSScriptRoot/Write-Section.ps1" -Title "Releasing $primaryTag"

    $archives = [ordered] @{}
    foreach ($pubProfile in $profiles) {
        $archivePath = & "$PSScriptRoot/Invoke-Publish.ps1" `
            -ProjectPath    $projPath `
            -PublishProfile $pubProfile.BaseName `
            -WorkspaceRoot  $WorkspaceRoot
        if ($LASTEXITCODE -ne 0) { exit 1 }

        $fileName = [System.IO.Path]::GetFileName($archivePath)
        # Strip "AssemblyName.Version." prefix and ".tgz" suffix to get the RID.
        $rid = $fileName -replace "^$([regex]::Escape("$assemblyName.$version."))(.+)\.tgz$", '$1'
        $archives[$rid] = $archivePath
    }

    $changelog = (& "$PSScriptRoot/Get-ChangelogEntry.ps1" -ProjectPath $projPath) -join "`n"

    # ── GitHub mode ───────────────────────────────────────────────────────────
    if ($isGitHub) {
        $notesFile = Join-Path $env:RUNNER_TEMP "release-notes-$assemblyName.md"
        $changelog | Set-Content -Path $notesFile -Encoding UTF8

        # Create and push the RID tags before creating the GitHub release, since `gh release create`
        # itself creates and pushes the primary tag remotely. Doing tags first means a failure here
        # is retried cleanly (tag creation is idempotent), whereas a failure after the release/primary
        # tag already exists would make the retry skip the project without ever finishing it.
        $ridTagList    = [System.Collections.Generic.List[string]]::new()
        $newRidTags    = [System.Collections.Generic.List[string]]::new()
        foreach ($rid in $archives.Keys) {
            $ridTag = "$assemblyName.$version.$rid"
            $existingRidTag = & git tag -l $ridTag
            if (-not $existingRidTag) {
                & git tag $ridTag
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "│   ❌ git tag '$ridTag' failed (exit code $LASTEXITCODE)." -ForegroundColor Red
                    exit 1
                }
                $newRidTags.Add($ridTag)
                Write-Host "│   📌 Staged tag: $ridTag" -ForegroundColor DarkGray
            }
            $ridTagList.Add("``$ridTag``")
        }

        if ($newRidTags.Count -gt 0) {
            & git push origin @($newRidTags)
            if ($LASTEXITCODE -ne 0) {
                Write-Host '│   ❌ git push of RID tags failed.' -ForegroundColor Red
                exit 1
            }
        }

        if (-not $releaseExists) {
            Write-Host "│   Creating GitHub release '$primaryTag'..." -ForegroundColor Cyan
            & gh release create $primaryTag @($archives.Values) --title $primaryTag --notes-file $notesFile
            if ($LASTEXITCODE -ne 0) {
                Write-Host "│   ❌ gh release create failed for '$primaryTag'." -ForegroundColor Red
                Write-Host "│   RID tags are already pushed, so the next run will pick up cleanly at the release step." -ForegroundColor Yellow
                exit 1
            }
        } else {
            $uploadPaths = @($archives.GetEnumerator() |
                Where-Object { [System.IO.Path]::GetFileName($_.Value) -notin $existingAssets } |
                ForEach-Object { $_.Value })
            Write-Host "│   Uploading $($uploadPaths.Count) missing asset(s) to existing release '$primaryTag'..." -ForegroundColor Cyan
            & gh release upload $primaryTag @uploadPaths
            if ($LASTEXITCODE -ne 0) {
                Write-Host "│   ❌ gh release upload failed for '$primaryTag'." -ForegroundColor Red
                exit 1
            }
        }

        $releaseUrl  = "https://github.com/$repo/releases/tag/$primaryTag"
        $ridTagsCell = $ridTagList -join '<br>'
        $summaryRows.Add("| [``$primaryTag``]($releaseUrl) | ``$version`` | $ridTagsCell |")

        if ($executableTarget.updaterReleaseName) {
            $assetUrls = [ordered] @{}
            foreach ($rid in $archives.Keys) {
                $filename        = [System.IO.Path]::GetFileName($archives[$rid])
                $assetUrls[$rid] = "https://github.com/$repo/releases/download/$primaryTag/$filename"
            }
            $updaterProjects[$assemblyName] = [ordered] @{
                version   = $version
                release   = $primaryTag
                changelog = $changelog
                assets    = $assetUrls
            }
        }

    # ── Local mode ────────────────────────────────────────────────────────────
    } else {
        $bundleDir = Join-Path $LocalReleaseDir $primaryTag
        New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null
        foreach ($archivePath in $archives.Values) {
            Copy-Item $archivePath -Destination $bundleDir
        }
        $changelog | Set-Content -Path (Join-Path $bundleDir 'release-notes.md') -Encoding UTF8

        Write-Host "└── ✅ Local bundle: $bundleDir" -ForegroundColor Green

        $ridTagsCell = ($archives.Keys | ForEach-Object { "``$assemblyName.$version.$_``" }) -join '<br>'
        $summaryRows.Add("| ``$primaryTag`` | ``$version`` | $ridTagsCell |")

        if ($executableTarget.updaterReleaseName) {
            $assetPaths = [ordered] @{}
            foreach ($rid in $archives.Keys) { $assetPaths[$rid] = $archives[$rid] }
            $updaterProjects[$assemblyName] = [ordered] @{
                version   = $version
                release   = $primaryTag
                changelog = $changelog
                assets    = $assetPaths
            }
        }

        if ($ShowTags) {
            Write-Host "  📌 Would tag: $primaryTag" -ForegroundColor Yellow
            foreach ($rid in $archives.Keys) {
                Write-Host "  📌 Would tag: $assemblyName.$version.$rid" -ForegroundColor Yellow
            }
        }
    }
}

# ── Post-loop: finalize ───────────────────────────────────────────────────────
# Runs even when no new release was created this run, so a previously failed/missed updater
# sync (e.g. all releases already complete but Update-UpdaterRelease itself failed last time)
# can still be repaired independently of whether anything new was released.
if ($isGitHub) {
    if ($executableTarget.updaterReleaseName -and $updaterProjects.Count -gt 0) {
        Update-UpdaterRelease -Projects $updaterProjects -Repo $repo -UpdaterTag $executableTarget.updaterReleaseName
    }
} elseif ($executableTarget.updaterReleaseName -and $updaterProjects.Count -gt 0) {
    $localJsonPath = Join-Path $LocalReleaseDir 'updater.json'
    if (Test-Path $localJsonPath) {
        $existing = Get-Content $localJsonPath -Raw | ConvertFrom-Json -AsHashtable
        if (-not $existing.projects) { $existing.projects = @{} }
        foreach ($key in $updaterProjects.Keys) { $existing.projects[$key] = $updaterProjects[$key] }
        $existing.generated = (Get-Date -Format 'o')
        $existing | ConvertTo-Json -Depth 10 | Set-Content -Path $localJsonPath -Encoding UTF8
    } else {
        [ordered] @{
            generated = (Get-Date -Format 'o')
            projects  = $updaterProjects
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $localJsonPath -Encoding UTF8
    }
    Write-Host "`n✅ Local updater.json: $localJsonPath" -ForegroundColor Green
}

if ($summaryRows.Count -eq 0) {
    Write-Host "`nNo new project versions — nothing to release." -ForegroundColor DarkGray
    if ($SummaryFile) {
        Add-Content -Path $SummaryFile -Value "### Releases`n`n_No new releases were created._`n" -Encoding UTF8
    }
    exit 0
}

if ($SummaryFile) {
    $tableRows = $summaryRows -join "`n"
    $md = @"
### Releases

| Release | Version | RID Tags |
|---|---|---|
$tableRows

"@
    Add-Content -Path $SummaryFile -Value $md -Encoding UTF8
}

Write-Host "`n✅ Executable release step complete." -ForegroundColor Green
exit 0
