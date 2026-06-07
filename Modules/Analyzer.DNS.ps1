Set-StrictMode -Version Latest

function Get-DnsCacheData {
    Get-DnsClientCache
}

function Get-DnsOperationalEvents {
    try {
        Get-WinEvent -LogName "Microsoft-Windows-DNS-Client/Operational" -ErrorAction Stop
    }
    catch {
        Write-Log -Level DEBUG -Message "Keine DNS Operational Events gefunden oder Zugriff verweigert."
        return @()
    }
}

function Build-DnsMap {
    param(
        [array]$DnsCache
    )

    $Map = @{}

    foreach ($Entry in $DnsCache) {
        try {
            # A-Record
            if ($Entry.Type -eq 1) {
                $Ip = [string]$Entry.Data
                $Hostname = [string]$Entry.Entry

                if (-not [string]::IsNullOrWhiteSpace($Ip) -and -not [string]::IsNullOrWhiteSpace($Hostname)) {
                    $Map[$Ip] = $Hostname
                }
            }
            # PTR-Record (Fallback)
            elseif ($Entry.Type -eq 12) {
                if ($Entry.Entry -match '^(\d+)\.(\d+)\.(\d+)\.(\d+)\.in-addr\.arpa$') {
                    $Ip = "$($Matches[4]).$($Matches[3]).$($Matches[2]).$($Matches[1])"
                    $Map[$Ip] = [string]$Entry.Data
                }
            }
        }
        catch {
            Write-Log -Level DEBUG -Message "Fehler beim Parsen des DNS-Eintrags: $($_.Exception.Message)"
        }
    }

    return $Map
}