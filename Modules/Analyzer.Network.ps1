Set-StrictMode -Version Latest

function Get-NetworkConnections {

    $Result = New-Object System.Collections.ArrayList
    
    # Optimierte Regex für private, lokale und APIPA IPs
    $PrivateIpRegex = '^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|169\.254\.)'

    # NEU: Wir erlauben auch abklingende Verbindungsstati (TimeWait, CloseWait etc.)
    # Dadurch erfassen wir kurze API-REST-Calls, die im 2-Sekunden-Takt sonst unsichtbar wären.
    $AllowedStates = @('Established', 'TimeWait', 'CloseWait', 'SynSent', 'SynReceived')

    foreach ($TrackedProcessId in $Global:TrackedPids) {
        try {
            $Process = Get-Process -Id $TrackedProcessId -ErrorAction Stop

            # TCP
            Get-NetTCPConnection -OwningProcess $TrackedProcessId -ErrorAction SilentlyContinue |
            Where-Object {
                $_.State -in $AllowedStates -and
                $_.RemoteAddress -and
                $_.RemoteAddress -ne '0.0.0.0' -and
                $_.RemoteAddress -ne '::' -and
                $_.RemotePort -gt 0 -and
                $_.RemoteAddress -notmatch $PrivateIpRegex
            } |
            ForEach-Object {
                [void]$Result.Add([PSCustomObject]@{
                    Timestamp  = Get-Date
                    PID        = $TrackedProcessId
                    Process    = $Process.ProcessName
                    Protocol   = "TCP"
                    LocalIP    = $_.LocalAddress
                    LocalPort  = $_.LocalPort
                    RemoteIP   = $_.RemoteAddress
                    RemotePort = $_.RemotePort
                    State      = $_.State
                })
            }
        }
        catch {
            Write-Log -Level DEBUG -Message "Fehler bei PID $TrackedProcessId : $($_.Exception.Message)"
        }
    }

    return $Result
}