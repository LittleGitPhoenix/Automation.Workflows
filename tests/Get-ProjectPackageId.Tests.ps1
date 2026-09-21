#Requires -Version 7
BeforeAll {
    Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force
    $script:ScriptPath  = "$PSScriptRoot/../scripts/Get-ProjectPackageId.ps1"
    $script:FixturesDir = "$PSScriptRoot/Fixtures/projects"
}

Describe 'Get-ProjectPackageId' {

    It 'returns an explicit PackageId property' {
        & $script:ScriptPath -ProjectPath "$script:FixturesDir/CustomPackageId.csproj" | Should -Be 'Foo.Package'
    }

    It 'defaults to AssemblyName (the project file name) when PackageId is not set' {
        & $script:ScriptPath -ProjectPath "$script:FixturesDir/ValidVersion.csproj" | Should -Be 'ValidVersion'
    }

    It 'defaults to an explicit AssemblyName when PackageId is not set' {
        & $script:ScriptPath -ProjectPath "$script:FixturesDir/CustomAssemblyName.csproj" | Should -Be 'Foo.Bar'
    }
}
