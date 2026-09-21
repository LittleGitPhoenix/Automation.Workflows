#Requires -Version 7
BeforeAll {
    Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force
    $script:ScriptPath  = "$PSScriptRoot/../scripts/Get-ProjectVersion.ps1"
    $script:FixturesDir = "$PSScriptRoot/Fixtures/projects"
}

Describe 'Get-ProjectVersion' {

    It 'returns all relevant version properties' {
        $result = & $script:ScriptPath -ProjectPath "$script:FixturesDir/ValidVersion.csproj"

        @($result.PSObject.Properties.Name) | Should -Be @('PackageVersion', 'Version')
        $result.Version | Should -Be '1.2.3'
    }

    It 'returns a prerelease Version property unchanged' {
        (& $script:ScriptPath -ProjectPath "$script:FixturesDir/PrereleaseVersion.csproj").Version | Should -Be '1.2.3-beta'
    }

    It 'falls back to the SDK default of 1.0.0 when Version is not set' {
        (& $script:ScriptPath -ProjectPath "$script:FixturesDir/NoVersion.csproj").Version | Should -Be '1.0.0'
    }
}
