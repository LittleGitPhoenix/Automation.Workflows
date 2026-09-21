#Requires -Version 7
BeforeAll {
    Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force
    $script:ScriptPath  = "$PSScriptRoot/../scripts/Get-ProjectAssemblyName.ps1"
    $script:FixturesDir = "$PSScriptRoot/Fixtures/projects"
}

Describe 'Get-ProjectAssemblyName' {

    It 'returns an explicit AssemblyName property' {
        & $script:ScriptPath -ProjectPath "$script:FixturesDir/CustomAssemblyName.csproj" | Should -Be 'Foo.Bar'
    }

    It 'defaults to the project file name when AssemblyName is not set' {
        & $script:ScriptPath -ProjectPath "$script:FixturesDir/ValidVersion.csproj" | Should -Be 'ValidVersion'
    }
}
