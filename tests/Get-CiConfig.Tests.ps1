#Requires -Version 7
BeforeAll {
    Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force
    $script:ScriptPath  = "$PSScriptRoot/../scripts/Get-CiConfig.ps1"
    $script:FixturesDir = "$PSScriptRoot/Fixtures/ci-config"
}

Describe 'Get-CiConfig' {

    It 'returns the config object with the expected properties for a minimal config' {
        $config = & $script:ScriptPath -WorkspaceRoot "$script:FixturesDir/valid-minimal" -ConfigPath "$script:FixturesDir/valid-minimal/ci-config.json"

        $config.solutionPath  | Should -Be 'src/Dummy.slnx'
        $config.coverageScope | Should -Be '[Dummy.*]*'
        $config.nugetDir      | Should -Be '.nuget'
    }

    It 'returns the config object with releaseTargets for a full config' {
        $config = & $script:ScriptPath -WorkspaceRoot "$script:FixturesDir/valid-full" -ConfigPath "$script:FixturesDir/valid-full/ci-config.json"

        $config.nugetDir              | Should -Be '.custom-nuget'
        $config.releaseTargets.Count  | Should -Be 2
        ($config.releaseTargets | Where-Object type -eq 'library').discover    | Should -Be $true
        ($config.releaseTargets | Where-Object type -eq 'executable').projects | Should -Contain 'src/Foo/Foo.csproj'
    }

    It 'fails when solutionPath is missing' {
        $result = Invoke-ScriptUnderTest -Path $script:ScriptPath -Arguments @{
            WorkspaceRoot = "$script:FixturesDir/valid-minimal"
            ConfigPath    = "$script:FixturesDir/invalid/missing-solutionpath.json"
        }

        $result.ExitCode | Should -Be 1
        $result.Output   | Should -Match "missing required property 'solutionPath'"
    }

    It 'fails when coverageScope is missing' {
        $result = Invoke-ScriptUnderTest -Path $script:ScriptPath -Arguments @{
            WorkspaceRoot = "$script:FixturesDir/valid-minimal"
            ConfigPath    = "$script:FixturesDir/invalid/missing-coveragescope.json"
        }

        $result.ExitCode | Should -Be 1
        $result.Output   | Should -Match "missing required property 'coverageScope'"
    }

    It 'fails when solutionPath does not resolve to an existing file' {
        $result = Invoke-ScriptUnderTest -Path $script:ScriptPath -Arguments @{
            WorkspaceRoot = "$script:FixturesDir/valid-minimal"
            ConfigPath    = "$script:FixturesDir/invalid/solutionpath-not-found.json"
        }

        $result.ExitCode | Should -Be 1
        $result.Output   | Should -Match 'does not resolve to an existing file'
    }

    It 'fails when solutionPath resolves to a directory instead of a file' {
        $result = Invoke-ScriptUnderTest -Path $script:ScriptPath -Arguments @{
            WorkspaceRoot = "$script:FixturesDir/valid-minimal"
            ConfigPath    = "$script:FixturesDir/invalid/solutionpath-is-directory.json"
        }

        $result.ExitCode | Should -Be 1
        $result.Output   | Should -Match 'does not resolve to an existing file'
    }

    It 'fails on an unknown releaseTargets type' {
        $result = Invoke-ScriptUnderTest -Path $script:ScriptPath -Arguments @{
            WorkspaceRoot = "$script:FixturesDir/valid-minimal"
            ConfigPath    = "$script:FixturesDir/invalid/unknown-releasetarget-type.json"
        }

        $result.ExitCode | Should -Be 1
        $result.Output   | Should -Match 'unknown type'
    }

    It 'fails on duplicate releaseTargets of the same type' {
        $result = Invoke-ScriptUnderTest -Path $script:ScriptPath -Arguments @{
            WorkspaceRoot = "$script:FixturesDir/valid-minimal"
            ConfigPath    = "$script:FixturesDir/invalid/duplicate-releasetarget-type.json"
        }

        $result.ExitCode | Should -Be 1
        $result.Output   | Should -Match 'at most one entry per type'
    }

    It 'fails when a library target has neither discover nor projects' {
        $result = Invoke-ScriptUnderTest -Path $script:ScriptPath -Arguments @{
            WorkspaceRoot = "$script:FixturesDir/valid-minimal"
            ConfigPath    = "$script:FixturesDir/invalid/library-no-discover-no-projects.json"
        }

        $result.ExitCode | Should -Be 1
        $result.Output   | Should -Match "'discover: true' or declare a non-empty 'projects' list"
    }

    It 'fails when an executable target has an empty projects list' {
        $result = Invoke-ScriptUnderTest -Path $script:ScriptPath -Arguments @{
            WorkspaceRoot = "$script:FixturesDir/valid-minimal"
            ConfigPath    = "$script:FixturesDir/invalid/executable-no-projects.json"
        }

        $result.ExitCode | Should -Be 1
        $result.Output   | Should -Match "must declare a non-empty 'projects' list"
    }
}
