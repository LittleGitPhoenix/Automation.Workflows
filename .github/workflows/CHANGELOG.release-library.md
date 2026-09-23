# Changelog

All notable changes to **release-library.yml** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

___

## 1.1.0

📅 _2026-09-23_
✏️ _Leistner_

### Added

- Added a new optional `environment` input that lets consumers configure the runner (operating system) used by the job. Defaults to `ubuntu-latest` as before.
- Added `NUGET_TOKEN` as an optional alternative to `NUGET_USER` for publishing to NuGet.org. This is necessary since NuGet's OIDC trusted publishing currently doesn't support reusable workflows (see [NuGet/login#9](https://github.com/NuGet/login/issues/9)). Both secrets are now optional, but at least one must be set or the new validation step fails fast. `NUGET_TOKEN` takes precedence over the OIDC login performed via `NUGET_USER` when both are present.
___

## 1.0.0

📅 _2026-09-21_
✏️ _Leistner_

Initial release.

### References

⚪ actions/checkout@v7
⚪ actions/setup-dotnet@v6
⚪ dorny/test-reporter@v3
⚪ NuGet/login@v1
⚪ Test-ProjectVersions.ps1 1.0.0
⚪ Test-PackageVersions.ps1 1.0.0
⚪ Test-ChangelogVersions.ps1 1.0.0
⚪ Invoke-Build.ps1 1.0.0
⚪ Invoke-Tests.ps1 1.0.0
⚪ Invoke-Release-Library.ps1 1.0.0
