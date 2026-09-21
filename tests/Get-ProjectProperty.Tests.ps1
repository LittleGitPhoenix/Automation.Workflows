#Requires -Version 7
BeforeAll {
    Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force
    $script:ScriptPath  = "$PSScriptRoot/../scripts/Get-ProjectProperty.ps1"
    $script:FixturesDir = "$PSScriptRoot/Fixtures/projects"
}

Describe 'Get-ProjectProperty' {

    It 'returns a single property as a bare value' {
        $value = & $script:ScriptPath -ProjectPath "$script:FixturesDir/ValidVersion.csproj" -Property Version

        $value | Should -Be '1.2.3'
    }

    It 'returns multiple properties as an object' {
        $value = & $script:ScriptPath -ProjectPath "$script:FixturesDir/CustomAssemblyName.csproj" -Property Version, AssemblyName

        $value.Version      | Should -Be '1.2.3'
        $value.AssemblyName | Should -Be 'Foo.Bar'
    }

    It 'returns control to the caller after a successful single-property call, instead of exiting the host process' {
        # If the script called exit on the success path, the second invocation below would never run.
        $first  = & $script:ScriptPath -ProjectPath "$script:FixturesDir/ValidVersion.csproj" -Property Version
        $second = & $script:ScriptPath -ProjectPath "$script:FixturesDir/CustomAssemblyName.csproj" -Property Version

        $first  | Should -Be '1.2.3'
        $second | Should -Be '1.2.3'
    }

    It 'fails for a nonexistent project path' {
        $result = Invoke-ScriptUnderTest -Path $script:ScriptPath -Arguments @{
            ProjectPath = "$script:FixturesDir/DoesNotExist.csproj"
            Property    = 'Version'
        }

        $result.ExitCode | Should -Be 1
    }
}
