<#PSScriptInfo
.VERSION 1.0.0
.GUID 4942ce18-1d20-491e-867f-80cc3a5d4dbc
.AUTHOR Felix Leistner
.COMPANYNAME Little Phoenix
.COPYRIGHT 2026 Little Phoenix
.TAGS ci cd powershell
.PROJECTURI https://github.com/LittleGitPhoenix/Automation.Workflows
#>

#Requires -Version 7
<#
.SYNOPSIS
    Verifies every release-relevant project's ⬙/CHANGELOG.md has an entry for its current version.
.DESCRIPTION
    Checks, for every project referenced by ci-config.json's releaseTargets (library discover/projects,
    executable projects):
      - A ⬙/CHANGELOG.md exists next to the project.
      - It has a "## <version>" heading matching the project's current Version.
      - If that entry has a date line (":calendar:" or the UTF-8 📅 emoji), it isn't a placeholder date (containing "?").
    A missing date line is reported as a warning only, since not every CHANGELOG uses one.
    Skipped entirely (with an info message) when ci-config.json declares no releaseTargets.
#>
param(
    [string] $WorkspaceRoot = [System.IO.Path]::GetFullPath("$PSScriptRoot/../.."),
    [string] $ConfigPath,
    [string] $SummaryFile
)

$ErrorActionPreference = 'Stop'

$config         = & "$PSScriptRoot/Get-CiConfig.ps1" -WorkspaceRoot $WorkspaceRoot -ConfigPath $ConfigPath
$releaseTargets = @($config.releaseTargets)

if ($releaseTargets.Count -eq 0) {
    Write-Host 'No releaseTargets configured - nothing to check.' -ForegroundColor DarkGray
    if ($SummaryFile) {
        Add-Content -Path $SummaryFile -Value "### Changelog Check`n`n_No releaseTargets configured - skipped._`n" -Encoding UTF8
    }
    exit 0
}

$projectsRoot = Join-Path $WorkspaceRoot ([System.IO.Path]::GetDirectoryName($config.solutionPath))

# ── Gather the same project set the release scripts would act on ─────────────
$projectPaths = [System.Collections.Generic.List[string]]::new()

$libraryTarget = $releaseTargets | Where-Object { $_.type -eq 'library' } | Select-Object -First 1
if ($libraryTarget) {
    if ($libraryTarget.discover) {
        Get-ChildItem -Path $projectsRoot -Recurse -Include '*.csproj' |
            Where-Object { [System.IO.Path]::GetRelativePath($projectsRoot, $_.FullName) -notmatch '(?i)(^|[/\\])Tests[/\\]' } |
            ForEach-Object { $projectPaths.Add($_.FullName) }
    } else {
        $libraryTarget.projects | ForEach-Object { $projectPaths.Add((Join-Path $WorkspaceRoot $_)) }
    }
}

$executableTarget = $releaseTargets | Where-Object { $_.type -eq 'executable' } | Select-Object -First 1
if ($executableTarget) {
    $executableTarget.projects | ForEach-Object { $projectPaths.Add((Join-Path $WorkspaceRoot $_)) }
}

Write-Host 'Checking changelog entries...' -ForegroundColor Cyan

$errors   = 0
$warnings = 0
$rows     = [System.Collections.Generic.List[string]]::new()
$dateRegex = '(?::calendar:|\ud83d\udcc5)\s*_([^_]+)_'

foreach ($projPath in $projectPaths) {
    $projFile      = Get-Item $projPath
    $version       = (& "$PSScriptRoot/Get-ProjectVersion.ps1" -ProjectPath $projPath).Version
    $projectDir    = [System.IO.Path]::GetDirectoryName($projPath)
    $changelogPath = Join-Path $projectDir "⬙/CHANGELOG.md"

    if (-not (Test-Path $changelogPath)) {
        Write-Host "  ❌  $($projFile.Name)  →  no ⬙/CHANGELOG.md found" -ForegroundColor Red
        $rows.Add("| ❌ | ``$($projFile.Name)`` | ``$version`` | CHANGELOG.md missing |")
        $errors++
        continue
    }

    $content      = Get-Content -Path $changelogPath -Raw
    $entryPattern = "(?ms)^##[ \t]+$([regex]::Escape($version))[ \t]*\r?\n(?<Body>.*?)(?=\r?\n_{3}|\r?\n##[ \t]|\z)"

    if ($content -notmatch $entryPattern) {
        Write-Host "  ❌  $($projFile.Name)  →  no '## $version' entry in CHANGELOG.md" -ForegroundColor Red
        $rows.Add("| ❌ | ``$($projFile.Name)`` | ``$version`` | No matching CHANGELOG entry |")
        $errors++
        continue
    }

    $entryBody = $Matches['Body']
    if ($entryBody -match $dateRegex) {
        $date = $Matches[1]
        if ($date -match '\?') {
            Write-Host "  ❌  $($projFile.Name)  →  version $version still has a placeholder date ('$date')" -ForegroundColor Red
            $rows.Add("| ❌ | ``$($projFile.Name)`` | ``$version`` | Placeholder date: ``$date`` |")
            $errors++
        } else {
            Write-Host "  ✅  $($projFile.Name)  →  $version ($date)" -ForegroundColor Green
            $rows.Add("| ✅ | ``$($projFile.Name)`` | ``$version`` | ``$date`` |")
        }
    } else {
        Write-Host "  ⚠️  $($projFile.Name)  →  version $version has no date line (warning only)" -ForegroundColor Yellow
        $rows.Add("| ⚠️ | ``$($projFile.Name)`` | ``$version`` | No date line found |")
        $warnings++
    }
}

if ($SummaryFile) {
    $tableRows = $rows -join "`n"
    $md = @"
### Changelog Check

| | Project | Version | Status |
|---|---|---|---|
$tableRows

"@
    Add-Content -Path $SummaryFile -Value $md -Encoding UTF8
}

if ($errors -gt 0) {
    Write-Host "`n❌ $errors changelog error(s)." -ForegroundColor Red
    exit 1
}

if ($warnings -gt 0) {
    Write-Host "`n⚠️  $warnings changelog warning(s), no errors." -ForegroundColor Yellow
}

Write-Host "`n✅ All changelog entries are valid." -ForegroundColor Green
exit 0
