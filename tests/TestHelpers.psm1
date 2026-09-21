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

    # Runs in a separate pwsh process, since the scripts under test call exit 0/exit 1 and
    # invoking them with `&` in this same process would let that exit terminate the Pester host.
    # Built as a -Command string (not -File), wrapped in try/catch, so an uncaught terminating
    # error (from Write-Error with $ErrorActionPreference = 'Stop') prints just its message -
    # matching what callers assert on - instead of pwsh's default multi-line error rendering.
    # Parameter names must stay unquoted so PowerShell still recognizes them as switches; only
    # values are quoted.
    # TestDrive:\ is a Pester-only PSDrive that doesn't exist in the child process, so any
    # TestDrive-rooted path is resolved to its real filesystem path first.
    $testDriveRoot = (Get-PSDrive -Name TestDrive -ErrorAction SilentlyContinue).Root
    function Resolve-TestDrivePath([string] $Value) {
        if ($testDriveRoot -and $Value -match '^TestDrive:[\\/]?') {
            $separator = [System.IO.Path]::DirectorySeparatorChar
            return $Value -replace '^TestDrive:[\\/]?', ($testDriveRoot.TrimEnd('\', '/') + $separator)
        }
        return $Value
    }

    $commandParts = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $Arguments.Keys) {
        $value = $Arguments[$key]
        if ($value -is [switch] -or $value -is [bool]) {
            if ($value) { $commandParts.Add("-$key") }
        } elseif ($value -is [array]) {
            $commandParts.Add("-$key")
            foreach ($item in $value) { $commandParts.Add("'" + ((Resolve-TestDrivePath ([string] $item)) -replace "'", "''") + "'") }
        } else {
            $commandParts.Add("-$key")
            $commandParts.Add("'" + ((Resolve-TestDrivePath ([string] $value)) -replace "'", "''") + "'")
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    try {
        $quotedPath  = "'" + ($Path -replace "'", "''") + "'"
        $commandText = "try { & $quotedPath $($commandParts -join ' ') } catch { Write-Output `$_.Exception.Message; exit 1 }"

        & pwsh -NoProfile -NonInteractive -Command $commandText *>&1 | ForEach-Object { $lines.Add($_.ToString()) }
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
