#Requires -Version 7
BeforeAll {
    Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force
}

Describe 'Invoke-ScriptUnderTest' {

    It 'captures the exit code of a script that calls exit on success' {
        $scriptPath = Join-Path $TestDrive 'exit-0.ps1'
        Set-Content -Path $scriptPath -Value "Write-Output 'done'`nexit 0"

        $result = Invoke-ScriptUnderTest -Path $scriptPath

        $result.ExitCode | Should -Be 0
        $result.Output   | Should -Contain 'done'
    }

    It 'captures the exit code of a script that calls exit on failure' {
        $scriptPath = Join-Path $TestDrive 'exit-1.ps1'
        Set-Content -Path $scriptPath -Value "Write-Error 'boom' -ErrorAction Continue`nexit 1"

        $result = Invoke-ScriptUnderTest -Path $scriptPath

        $result.ExitCode | Should -Be 1
    }

    It 'still runs after a previous script under test called exit, proving the host process survives' {
        # If Invoke-ScriptUnderTest ran the script in-process, the previous test's `exit` call
        # would have terminated the whole Pester run, and this test would never execute.
        $true | Should -Be $true
    }
}
