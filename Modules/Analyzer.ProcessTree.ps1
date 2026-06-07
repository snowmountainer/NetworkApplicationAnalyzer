Set-StrictMode -Version Latest

function Initialize-ProcessTracking {
    $Global:TrackedPids = New-Object System.Collections.Generic.HashSet[int]
}

function Add-RootProcess {
    param(
        [int]$ProcessId
    )
    [void]$Global:TrackedPids.Add($ProcessId)
}

function Update-ProcessTree {

    #
    # Erst neue Kinder erkennen
    #

    $Processes =
        Get-CimInstance Win32_Process

    foreach($Process in $Processes)
    {
        if(
            $Global:TrackedPids.Contains(
                [int]$Process.ParentProcessId
            )
        )
        {
            [void]$Global:TrackedPids.Add(
                [int]$Process.ProcessId
            )
        }
    }

    #
    # Danach tote PIDs entfernen
    #

    $DeadPids = @()

    foreach($TrackedPid in $Global:TrackedPids)
    {
        try
        {
            Get-Process `
                -Id $TrackedPid `
                -ErrorAction Stop | Out-Null
        }
        catch
        {
            $DeadPids += $TrackedPid
        }
    }

    foreach($DeadPid in $DeadPids)
    {
        [void]$Global:TrackedPids.Remove($DeadPid)
    }
}

