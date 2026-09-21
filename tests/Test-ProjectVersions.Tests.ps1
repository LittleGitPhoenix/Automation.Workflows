#Requires -Version 7
BeforeAll {
    Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force
    $script:ScriptPath  = "$PSScriptRoot/../scripts/Test-ProjectVersions.ps1"
    $script:FixturesDir = "$PSScriptRoot/Fixtures/project-versions"
}

Describe 'Test-ProjectVersions' {

    It 'passes when all discovered projects have valid SemVer versions, excluding the Tests folder' {
        $result = Invoke-ScriptUnderTest -Path $script:ScriptPath -Arguments @{
            WorkspaceRoot = "$script:FixturesDir/AllValid"
            ConfigPath    = "$script:FixturesDir/AllValid/ci-config.json"
        }

        $result.ExitCode | Should -Be 0
        # ExcludedBad.csproj lives under a 'Tests' folder and has an invalid Version - proves the exclusion filter works.
        ($result.Output -join "`n") | Should -Not -Match 'ExcludedBad'
    }

    It 'fails and reports the offending project when one has an invalid version' {
        $summaryFile = "TestDrive:/summary.md"
        $result = Invoke-ScriptUnderTest -Path $script:ScriptPath -Arguments @{
            WorkspaceRoot = "$script:FixturesDir/OneInvalid"
            ConfigPath    = "$script:FixturesDir/OneInvalid/ci-config.json"
            SummaryFile   = $summaryFile
        }

        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'BadLib\.csproj'
        ($result.Output -join "`n") | Should -Match 'AssemblyVersion'

        Get-Content $summaryFile -Raw | Should -Match 'BadLib\.csproj'
    }

    It 'fails on a version with a leading zero in a numeric component' {
        $result = Invoke-ScriptUnderTest -Path $script:ScriptPath -Arguments @{
            WorkspaceRoot = "$script:FixturesDir/LeadingZero"
            ConfigPath    = "$script:FixturesDir/LeadingZero/ci-config.json"
        }

        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'LeadingZeroLib\.csproj'
    }
}
