Set-StrictMode -Version Latest

function Start-NetworkTrace {
    param(
        [string]$TraceFile
    )

    Write-Log "Starting netsh trace"
    netsh trace start scenario=InternetClient capture=yes tracefile="$TraceFile" persistent=no maxsize=512 | Out-Null
}

function Stop-NetworkTrace {
    Write-Log "Stopping netsh trace"

    try {
        $Job = Start-Job -ScriptBlock { netsh trace stop }

        if (-not (Wait-Job $Job -Timeout 120)) {
            Write-Log -Level WARN -Message "netsh trace stop timeout nach 120 Sekunden"
            Stop-Job $Job -Force
        }

        Receive-Job $Job | Out-Null
        Remove-Job $Job -Force
    }
    catch {
        Write-Exception $_
    }
}