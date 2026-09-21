# Automation.Workflows

Reusable GitHub Actions workflows and PowerShell scripts for Phoenix repositories. A consuming repository provides a small `.github/ci-config.json` plus a couple of thin wrapper files, and gets version checks, build, tests with coverage, PR test reporting and releases (NuGet packages or self-contained executables) for free.

The same scripts also run locally without any GitHub Actions involved, so a full validate/release run can be reproduced on a developer machine before pushing.

___

## What this repository provides

- **`scripts/`**: Generic PowerShell scripts (`#Requires -Version 7`) that do the actual work (version checks, build, tests, packaging, releasing). They read repository-specific settings from a consumer's `.github/ci-config.json` and know nothing else about the consuming repo.
- **`.github/workflows/`**: Reusable GitHub Actions workflows (`workflow_call`) that check out the consumer repository as well as this repository (to be able to use the scripts), then call the scripts in sequence.

  | Workflow | Purpose |
  | --- | --- |
  | `validate.yml` | Version checks + build + tests with coverage + PR check annotations. No release step. |
  | `release-library.yml` | Same as `validate.yml`, then packs and releases NuGet packages (GitHub release + push to NuGet.org). |
  | `release-executable.yml` | Same as `validate.yml`, then publishes self-contained executables and creates GitHub releases (optionally updates an auto-updater index). |

A consuming repository never calls these scripts directly in CI. It only references the reusable workflows via `uses:`. Locally, a thin per-repo wrapper (`.github/scripts/Invoke-CI.ps1`) forwards to `scripts/Invoke-CI.ps1` in this repository, which chains the same scripts the workflows use.

___

## `ci-config.json`

Every consuming repository needs a `.github/ci-config.json` (a different path can be passed via the `config-path` workflow input / `-ConfigPath` script parameter). It is the single source of repository-specific settings.

```json
{
  // Required. Path to the solution file, relative to the repository root.
  "solutionPath": "src/Foo.sln",

  // Required. coverlet --coverlet-include pattern, e.g. "[MyCompany.MyProduct.*]*".
  "coverageScope": "[Phoenix.Functionality.Logging.*]*",

  // Optional. coverlet --coverlet-exclude pattern. Typically excludes test assemblies.
  "coverageExclude": "[*.Test]*",

  // Optional, default ".nuget". Folder (relative to the repo root) that built .nupkg files land in.
  "nugetDir": ".nuget",

  // Optional. Required for Release mode / the release-* workflows. One entry per release type.
  "releaseTargets": [
    // Library repos: releases every discovered project's .nupkg as a GitHub release + NuGet.org push.
    { "type": "library", "discover": true },

    // Alternative: only release specific projects instead of auto-discovering all non-test .csproj.
    // { "type": "library", "projects": [ "src/Foo/Foo.csproj" ] },

    // Executable repos: publishes the given project(s) using their PublishProfiles, one GitHub release per project with all RID archives attached.
    {
      "type": "executable",
      "projects": [ "src/Foo/Foo.csproj" ],
      "publishProfilesDir": "Properties/PublishProfiles",
      "updaterReleaseName": "Foo-Updater"
    }
  ]
}
```

Notes:

- `releaseTargets` may contain at most one `library` and one `executable` entry. Multiple projects are then specified via the `projects` list. A repository can declare both if it produces a NuGet package and a companion executable.
- `library` with `discover: true` picks up every non-test `*.csproj` under `solutionPath`'s folder. Omit `discover` and use `projects` instead to release only specific projects.
- `executable` always requires an explicit `projects` list (no discovery). Each project needs `Properties/PublishProfiles/*.pubxml` files (profiles with `local only` in the name are skipped by the release script). Building the archives themselves relies on the consumer's own MSBuild targets, see [Requirements for a consuming repository](#requirements-for-a-consuming-repository) below.
- `updaterReleaseName` is optional and only relevant for `executable` targets that participate in an auto-updater index release (`updater.json`).

___

## Using the reusable workflows in another repository

### 1. Add `.github/ci-config.json`

See the example above. At minimum `solutionPath` and `coverageScope` are required for validation. Add `releaseTargets` once releases are needed.

### 2. Add thin caller workflows

`.github/workflows/validation.yml`:

```yaml
name: Validation

on:
  workflow_dispatch:
  pull_request:
    branches: [ "main" ]

jobs:
  validate:
    uses: LittleGitPhoenix/Automation.Workflows/.github/workflows/validate.yml@v1
```

`.github/workflows/release.yml` (NuGet library repo):

```yaml
name: Release

on:
  workflow_dispatch:
  push:
    branches: [ "main" ]

permissions:
  contents: write
  id-token: write

jobs:
  release:
    uses: LittleGitPhoenix/Automation.Workflows/.github/workflows/release-library.yml@v1
    secrets:
      NUGET_USER: ${{ secrets.NUGET_USER }}
```

`release-library.yml` publishes to NuGet.org via [Trusted Publishing](https://learn.microsoft.com/en-us/nuget/nuget-org/trusted-publishing) (OIDC), not a long-lived API key. This requires:

- A Trusted Publishing policy registered on nuget.org for the package owner, with Repository Owner/Repository matching the *consumer* repo and Workflow File set to the consumer's own workflow filename (e.g. `release.yml`) - not the reusable workflow's path in this repository.

- The job calling the reusable workflow must grant `permissions: id-token: write` (shown above). It is never inherited from repository defaults, unlike other scopes.

	> [!NOTE]
	>
	> Once a job or workflow declares its own `permissions:` block, every scope not listed is implicitly set to `none` rather than falling back to the repo default, so `contents: write` must be listed alongside it too or the release step's git tag push and `gh release create` calls will fail.

- A `NUGET_USER` secret in the consumer repo holding the nuget.org username.

For an executable repo, use `release-executable.yml` instead (no NuGet publishing at all; it uses the automatically provided `GITHUB_TOKEN`).

### 3. Add a local CI wrapper (optional, but recommended)

Add `.github/scripts/Invoke-CI.ps1` in the consuming repo. It forwards to a local clone of this repository whose local path must be defined by the **`PHOENIX_REUSABLE_WORKFLOWS_REPOSITORY_PATH`** environment variable.

```powershell
#Requires -Version 7
param(
    [ValidateSet('Validate', 'Release', 'All')]
    [string] $Mode,
    [switch] $CreateTags
)

$ErrorActionPreference = 'Stop'

$toolsPath = $env:PHOENIX_REUSABLE_WORKFLOWS_REPOSITORY_PATH
if (-not $toolsPath -or -not (Test-Path $toolsPath)) {
    Write-Error "Set PHOENIX_REUSABLE_WORKFLOWS_REPOSITORY_PATH to a local clone of https://github.com/LittleGitPhoenix/Automation.Workflows"
    exit 1
}

$repoRoot = [System.IO.Path]::GetFullPath("$PSScriptRoot/../..")
$params = @{ WorkspaceRoot = $repoRoot }
if ($Mode) { $params['Mode'] = $Mode }
if ($CreateTags) { $params['CreateTags'] = $true }

& (Join-Path $toolsPath 'scripts/Invoke-CI.ps1') @params
exit $LASTEXITCODE
```

Then, with the environment variable set once per machine:

```powershell
$env:PHOENIX_REUSABLE_WORKFLOWS_REPOSITORY_PATH = 'D:\GIT\Phoenix\Automation.Workflows'
.\.github\scripts\Invoke-CI.ps1 -Mode Validate
.\.github\scripts\Invoke-CI.ps1 -Mode Release   # creates a local release bundle, never touches NuGet.org/GitHub
```

Locally, `Invoke-CI.ps1` always behaves as if running outside GitHub Actions: Releases are copied into `.publish/local-release/<timestamp>/` instead of being published, and no NuGet/GitHub calls or `git push` happen unless explicitly run in a GitHub Actions runner (`GITHUB_ACTIONS=true`).

___

## Requirements for a consuming repository

- .NET SDK matching the `dotnet-version` workflow input (default `10.0.x`).
- All projects:
  - Have a `⬙/CHANGELOG.md` (read by `Get-ChangelogEntry.ps1` for release notes).
  - Use a `Version` that follows [SemVer](https://semver.org/). This is enforced by `Test-ProjectVersions.ps1`.
- Test projects:
  - Use Microsoft Testing Platform (MTP) using NUnit, with `coverlet.MTP` for coverage and result files matching `**/TestResults/*.test.result.xml`.
- For **`library` releases**:
  - `GeneratePackageOnBuild` producing a `.nupkg` per project under `nugetDir`.
- For **`executable` releases**:
    - `Properties/PublishProfiles/*.pubxml` per RID
    - `Invoke-Publish.ps1` expects a `.tgz` archive at `.publish/{AssemblyName}/{AssemblyName}.{Version}.{RID}.tgz` after `dotnet publish` completes. Plain `dotnet publish` doesn't create this, so the consuming project must produce it itself, typically via a `SetupPropertiesAfterPublish` target that computes `ArchiveFilePath` from the publish output and a `CreateArchive` target that `tar`s it into place (see `Application.Mandos/src/common.targets` for a working example). This build logic is intentionally not part of this repository since it is app-specific.
___

## Example consumer

`Functionality.Logging.Extensions` is wired up exactly as described above: [`ci-config.json`](https://github.com/LittleGitPhoenix/Functionality.Logging.Extensions/blob/main/.github/ci-config.json), [`validation.yml`](https://github.com/LittleGitPhoenix/Functionality.Logging.Extensions/blob/main/.github/workflows/validation.yml), [`release.yml`](https://github.com/LittleGitPhoenix/Functionality.Logging.Extensions/blob/main/.github/workflows/release.yml) and [`Invoke-CI.ps1`](https://github.com/LittleGitPhoenix/Functionality.Logging.Extensions/blob/main/.github/scripts/Invoke-CI.ps1).
___

## Testing the scripts

`tests/` contains a manual [Pester](https://github.com/pester/pester) (v6+) test suite covering the validation scripts (`Get-CiConfig.ps1`, `Get-ChangelogEntry.ps1`, `Get-ProjectProperty.ps1`, `Get-ProjectVersion.ps1`, `Get-ProjectAssemblyName.ps1`, `Get-ProjectPackageId.ps1`, `Test-ProjectVersions.ps1`, `Test-ChangelogVersions.ps1`) against fixtures under `tests/Fixtures/`. It is a local developer tool, not part of any CI workflow, since this repository itself provides the CI/CD pipeline for other repos.

Requirements: PowerShell 7, a local .NET SDK (some tests shell out to `dotnet msbuild`), and Pester 6+ (installed automatically on first run if missing).

```powershell
pwsh tests/Invoke-ScriptTests.ps1
```
