<#PSScriptInfo
.VERSION 1.0.0
.GUID 370c3d9b-35b0-4e9a-a39b-41328d88b035
.AUTHOR Felix Leistner
.COMPANYNAME Little Phoenix
.COPYRIGHT 2026 Little Phoenix
.TAGS ci cd powershell
.PROJECTURI https://github.com/LittleGitPhoenix/Automation.Workflows
#>

#Requires -Version 7
param(
    [string] $WorkspaceRoot = [System.IO.Path]::GetFullPath("$PSScriptRoot/../.."),
    [string] $ConfigPath,
    [string] $Configuration = 'Release',
    [string] $OutputDir,
    [string] $SummaryFile
)

$ErrorActionPreference = 'Stop'

$config = & "$PSScriptRoot/Get-CiConfig.ps1" -WorkspaceRoot $WorkspaceRoot -ConfigPath $ConfigPath

if (-not $OutputDir) {
    $OutputDir = Join-Path $WorkspaceRoot 'TestResults'
}

$reportDir    = Join-Path $OutputDir 'coverage-report'
$sln          = Join-Path $WorkspaceRoot $config.solutionPath
$solutionDir  = [System.IO.Path]::GetDirectoryName($sln)

New-Item -ItemType Directory -Force -Path $OutputDir  | Out-Null
New-Item -ItemType Directory -Force -Path $reportDir  | Out-Null

# Remove stale coverage XMLs so the report never references deleted source files.
Get-ChildItem -Path $OutputDir -Filter '*.coverage.cobertura.*.xml' -ErrorAction SilentlyContinue | Remove-Item -Force

# ── Run tests ─────────────────────────────────────────────────────────────────
# Uses coverlet.MTP for code coverage and NunitXml.TestLogger (Spekt) for
# NUnit XML test result files.
#
# IMPORTANT: dotnet test finds global.json (which opts into the MTP runner
# instead of the legacy VSTest MSBuild target) by walking UP from the current
# working directory, not from the solution path. global.json must live next
# to the solution, so the test run must be invoked from that directory.
Write-Host "Running tests for '$sln'..." -ForegroundColor Cyan

$testArgs = @(
    $sln,
    '-c', $Configuration,
    '--no-build',
    '--ignore-exit-code', '8',   # MTP exits 8 when an assembly runs zero tests (all filtered out); treat as success
    '--filter', 'FullyQualifiedName!~IntegrationTest',
    '--results-directory', $OutputDir,
    # Spekt NUnit XML reporter — consumed by dorny/test-reporter (dotnet-nunit) on CI.
    '--report-spekt-nunit',
    '--report-spekt-nunit-filename', '{assembly}.{framework}.test.result.xml',
    # Coverage via coverlet.MTP. The output file prefix is set per-project via
    # TestingPlatformCommandLineArguments in each test .csproj.
    '--coverlet',
    '--coverlet-output-format', 'cobertura',
    '--coverlet-include',                          $config.coverageScope,
    '--coverlet-exclude-assemblies-without-sources', 'MissingAll',
    '--coverlet-exclude-by-file',                  '**/*.g.cs'
)
if ($config.coverageExclude) {
    $testArgs += @('--coverlet-exclude', $config.coverageExclude)
}

Push-Location $solutionDir
try {
    & dotnet test @testArgs
    $testExitCode = $LASTEXITCODE
} finally {
    Pop-Location
    # The MTP runner uses ANSI escape sequences that may leave the terminal in a
    # colored state. Reset explicitly so the caller's prompt keeps its normal color.
    [Console]::ResetColor()
}

# ── Test results summary ──────────────────────────────────────────────────────
if ($SummaryFile) {
    $resultFiles = Get-ChildItem -Path $OutputDir -Filter '*.test.result.xml' -ErrorAction SilentlyContinue
    $rows        = [System.Collections.Generic.List[string]]::new()
    $totalAll = 0; $passedAll = 0; $failedAll = 0; $skippedAll = 0

    foreach ($f in $resultFiles) {
        $xml      = [xml](Get-Content -Path $f.FullName -Raw)
        $run      = $xml.SelectSingleNode('/test-run')
        $total    = [int]$run.total
        $passed   = [int]$run.passed
        $failed   = [int]$run.failed
        $skipped  = [int]$run.skipped
        $assembly = [System.IO.Path]::GetFileNameWithoutExtension($f.Name) -replace '\.NETCoreApp[^.]+\.test\.result$', ''
        $icon     = if ($failed -gt 0) { '❌' } else { '✅' }
        $rows.Add("| $icon | ``$assembly`` | $total | $passed | $failed | $skipped |")
        $totalAll   += $total
        $passedAll  += $passed
        $failedAll  += $failed
        $skippedAll += $skipped
    }

    if ($rows.Count -gt 0) {
        $rows.Add("|  | **Total** | **$totalAll** | **$passedAll** | **$failedAll** | **$skippedAll** |")
        $tableRows = $rows -join "`n"
        $md = @"
### Test Results

| | Assembly | Total | Passed | Failed | Skipped |
|---|---|---|---|---|---|
$tableRows

"@
        Add-Content -Path $SummaryFile -Value $md -Encoding UTF8
    }
}

# ── Coverage report (ReportGenerator) ────────────────────────────────────────
# coverlet.MTP produces files named:  {prefix}.coverage.cobertura.{n}.xml
# The prefix is set via --coverlet-file-prefix (TestingPlatformCommandLineArguments).
Write-Host "`nGenerating coverage report..." -ForegroundColor Cyan

$reportGeneratorVersion = '5.5.11'

& dotnet tool update --global dotnet-reportgenerator-globaltool --version $reportGeneratorVersion
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to install/update dotnet-reportgenerator-globaltool $reportGeneratorVersion." -ForegroundColor Red
    exit 1
}

# Make sure the global tools directory is on PATH for this session.
$toolsPath = Join-Path $HOME '.dotnet/tools'
if ((Test-Path $toolsPath) -and ($env:PATH -notlike "*$toolsPath*")) {
    $env:PATH = $toolsPath + [System.IO.Path]::PathSeparator + $env:PATH
}

$coberturaFiles = Get-ChildItem -Path $OutputDir -Recurse -Filter '*.coverage.cobertura.*.xml' -ErrorAction SilentlyContinue

if ($coberturaFiles) {
    # Resolve files explicitly and join with semicolons.
    # Passing a glob directly to ReportGenerator -reports: triggers its own
    # internal expansion which emits "Duplicate command line parameter" warnings
    # and silently discards all files except the last one.
    $reportsParam = ($coberturaFiles.FullName -join ';')

    & reportgenerator `
        "-reports:$reportsParam" `
        "-targetdir:$reportDir" `
        '-reporttypes:Html;MarkdownAssembliesSummary' `
        '-verbosity:Warning'

    if ($LASTEXITCODE -ne 0) {
        Write-Host '⚠️  ReportGenerator exited with a non-zero exit code; coverage report may be incomplete.' -ForegroundColor Yellow
    } else {
        Write-Host "✅ Coverage report: $(Join-Path $reportDir 'index.html')" -ForegroundColor Green
    }

    $summaryMd = Join-Path $reportDir 'Summary.md'
    if ($SummaryFile -and (Test-Path $summaryMd)) {
        Add-Content -Path $SummaryFile -Value "`n### Code Coverage`n" -Encoding UTF8
        Get-Content -Path $summaryMd | Add-Content -Path $SummaryFile -Encoding UTF8
    } elseif ($SummaryFile) {
        Add-Content -Path $SummaryFile -Value "`n### Code Coverage`n`n⚠️ Coverage report could not be generated.`n" -Encoding UTF8
    }
} else {
    Write-Host '⚠️  No coverage XML files found; report skipped.' -ForegroundColor Yellow
}

# ── Result ────────────────────────────────────────────────────────────────────
if ($testExitCode -ne 0) {
    Write-Host "`n❌ Tests failed." -ForegroundColor Red
    exit 1
}

Write-Host "`n✅ All tests passed." -ForegroundColor Green
exit 0
