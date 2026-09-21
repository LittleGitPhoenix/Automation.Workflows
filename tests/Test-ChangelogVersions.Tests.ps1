#Requires -Version 7
BeforeAll {
    Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force
    $script:ScriptPath  = "$PSScriptRoot/../scripts/Test-ChangelogVersions.ps1"
    $script:FixturesDir = "$PSScriptRoot/Fixtures/changelog"
}

Describe 'Test-ChangelogVersions' {

    It 'passes with only a warning when entries are valid or merely missing a date line' {
        $result = Invoke-ScriptUnderTest -Path $script:ScriptPath -Arguments @{
            WorkspaceRoot = $script:FixturesDir
            ConfigPath    = "$script:FixturesDir/ci-config-all-valid.json"
        }

        $result.ExitCode | Should -Be 0
        ($result.Output -join "`n") | Should -Match 'warning'
    }

    It 'fails when a project has a missing changelog, no matching entry, or a placeholder date' {
        $summaryFile = "TestDrive:/summary.md"
        $result = Invoke-ScriptUnderTest -Path $script:ScriptPath -Arguments @{
            WorkspaceRoot = $script:FixturesDir
            ConfigPath    = "$script:FixturesDir/ci-config-with-errors.json"
            SummaryFile   = $summaryFile
        }

        $result.ExitCode | Should -Be 1
        $combinedOutput = $result.Output -join "`n"
        $combinedOutput  | Should -Match 'MissingChangelog\.csproj'
        $combinedOutput  | Should -Match 'NoMatchingEntry\.csproj'
        $combinedOutput  | Should -Match 'WithPlaceholderDate\.csproj'

        $summary = Get-Content $summaryFile -Raw
        $summary | Should -Match 'CHANGELOG.md missing'
        $summary | Should -Match 'Placeholder date'
    }
}
