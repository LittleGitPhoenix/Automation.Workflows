#Requires -Version 7
BeforeAll {
    Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force
    $script:ScriptPath  = "$PSScriptRoot/../scripts/Get-ChangelogEntry.ps1"
    $script:FixturesDir = "$PSScriptRoot/Fixtures/changelog"
}

Describe 'Get-ChangelogEntry' {

    It 'extracts the newest entry, stopping at the ___ separator' {
        $entry = & $script:ScriptPath -ProjectPath "$script:FixturesDir/WithValidEntry/WithValidEntry.csproj"

        $entry | Should -Match '^## 1\.2\.3'
        $entry | Should -Not -Match '1\.0\.0'
    }

    It 'extracts the only entry when there is no ___ separator' {
        $entry = & $script:ScriptPath -ProjectPath "$script:FixturesDir/NoDateLine/NoDateLine.csproj"

        $entry | Should -Match '^## 1\.2\.3'
        $entry | Should -Match 'no date line present'
    }

    It 'fails when the ⬙/CHANGELOG.md file does not exist' {
        $result = Invoke-ScriptUnderTest -Path $script:ScriptPath -Arguments @{
            ProjectPath = "$script:FixturesDir/MissingChangelog/MissingChangelog.csproj"
        }

        $result.ExitCode | Should -Be 1
        $result.Output   | Should -Match 'CHANGELOG not found'
    }
}
