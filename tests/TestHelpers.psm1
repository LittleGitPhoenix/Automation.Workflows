#Requires -Version 7
<#
.SYNOPSIS
    Shared helper for the manual Pester test suite under tests/.
#>

function Invoke-ScriptUnderTest {
    <#
    .SYNOPSIS
        Runs a script under test, capturing combined output and exit code.
    #>
    param(
        [Parameter(Mandatory)] [string]   $Path,
        [hashtable]                       $Arguments = @{}
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    try {
        # The scripts under test set $ErrorActionPreference = 'Stop', so their Write-Error calls
        # become terminating exceptions that skip past *>&1 and must be caught explicitly here.
        # *>&1 (not just 2>&1) is needed because status messages use Write-Host, which in pwsh
        # goes through the Information stream (6), not the success output stream.
        & $Path @Arguments *>&1 | ForEach-Object { $lines.Add($_.ToString()) }
        $exitCode = $LASTEXITCODE
    } catch {
        $lines.Add($_.ToString())
        $exitCode = 1
    }

    [pscustomobject] @{
        Output   = $lines.ToArray()
        ExitCode = $exitCode
    }
}

Export-ModuleMember -Function Invoke-ScriptUnderTest
