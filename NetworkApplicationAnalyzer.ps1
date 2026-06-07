[CmdletBinding()]
param(

    [Parameter(Mandatory)]
    [string]$Executable,

    [string]$Arguments = "",

    [int]$DurationSeconds = 60,

    [int]$PollingIntervalSeconds = 1,

    [switch]$EnableProcmon
)

Set-StrictMode -Version Latest

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Explizites Laden der Module
$Modules = @(
    "Analyzer.Logging.ps1",
    "Analyzer.ProcessTree.ps1",
    "Analyzer.Network.ps1",
    "Analyzer.DNS.ps1",
    "Analyzer.Reporting.ps1",
    "Analyzer.NetTrace.ps1",
    "Analyzer.Procmon.ps1"
)

foreach ($Module in $Modules) {
    $ModulePath = Join-Path $ScriptRoot "Modules\$Module"
    if (Test-Path $ModulePath) {
        . $ModulePath
    } else {
        Write-Warning "Kritisches Modul nicht gefunden: $ModulePath"
        return
    }
}
$ReportVersion = "1.0"
$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputFolder = Join-Path $ScriptRoot "Reports\$RunId"

New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

$ProcmonPath = Join-Path $ScriptRoot "Procmon64.exe"
$PmlFile     = Join-Path $OutputFolder "Procmon.pml"
$TraceFile   = Join-Path $OutputFolder "NetTrace.etl"

Initialize-Logging -OutputFolder $OutputFolder
Initialize-ProcessTracking

if ($EnableProcmon) {
    Write-Log "Starting Procmon"
    Start-Procmon -ProcmonPath $ProcmonPath -PmlFile $PmlFile
} else {
    Write-Log "Procmon disabled"
}

Write-Log "Starting netsh trace"
#Start-NetworkTrace -TraceFile $TraceFile

try {
    Write-Log "Launching application: $Executable"

    $ProcessParams = @{
        FilePath    = $Executable
        PassThru    = $true
        ErrorAction = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
        $ProcessParams.ArgumentList = $Arguments
    }

    $RootProcess = Start-Process @ProcessParams
    Write-Log "Root PID: $($RootProcess.Id)"

    Add-RootProcess -ProcessId $RootProcess.Id
    
    Write-Log "Starting monitoring loop"

    $AllConnections  = New-Object System.Collections.ArrayList
    $AllDnsSnapshots = New-Object System.Collections.ArrayList
    $AllProcessTree  = New-Object System.Collections.ArrayList

    $EndTime = (Get-Date).AddSeconds($DurationSeconds)

    while ((Get-Date) -lt $EndTime) {
        try {
            Update-ProcessTree

            foreach ($TrackedProcessId in $Global:TrackedPids) {
                [void]$AllProcessTree.Add([PSCustomObject]@{
                    Timestamp = Get-Date
                    ProcessId = $TrackedProcessId
                })
            }

            $CurrentConnections = Get-NetworkConnections
            if ($CurrentConnections) {
                # KORREKTUR: Expliziter Cast auf [array], um Unrolling-Fehler bei Einzelobjekten zu vermeiden
                $AllConnections.AddRange([array]$CurrentConnections)
            }

            $CurrentDns = Get-DnsCacheData
            if ($CurrentDns) {
                # KORREKTUR: Auch hier zur Sicherheit als [array] casten
                $AllDnsSnapshots.AddRange([array]$CurrentDns)
            }

            Write-Log ("Tracked Processes: {0} | Connections: {1}" -f $Global:TrackedPids.Count, $AllConnections.Count)
        }
        catch {
            Write-Exception $_
        }
        Start-Sleep -Seconds $PollingIntervalSeconds
    }
    Write-Log "Monitoring finished"    
}
catch {
    Write-Exception $_
    throw
}
finally {
    try {
        #Write-Log "Stopping network trace"
        #Stop-NetworkTrace
    }
    catch {
        Write-Exception $_
    }

    if ($EnableProcmon) {
        $ProcmonCsv = Join-Path $OutputFolder "Procmon.csv"
        try {
            Write-Log "Stopping Procmon"
            Stop-Procmon -ProcmonPath $ProcmonPath -PmlFile $PmlFile -CsvFile $ProcmonCsv
        }
        catch {
            Write-Exception $_
        }
    }
}

Write-Log "Collecting DNS client events"
$DnsEvents = Get-DnsOperationalEvents

Write-Log "Building DNS map"
$DnsMap = Build-DnsMap -DnsCache $AllDnsSnapshots
Write-Log "DNS map entries: $($DnsMap.Count)"

$FilteredConnections = $AllConnections | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_.RemoteIP) -and
    $_.RemoteIP -notmatch '^127\.|^169\.254\.' -and
    $_.RemoteIP -notin @('0.0.0.0', '::', '::1') -and
    $_.RemotePort -gt 0
}

$Combined = New-Object System.Collections.ArrayList

foreach ($Connection in $FilteredConnections) {
    $Hostname = $null

    if ($DnsMap.ContainsKey($Connection.RemoteIP)) {
        $Hostname = $DnsMap[$Connection.RemoteIP]
    }

    [void]$Combined.Add([PSCustomObject]@{
        Timestamp  = $Connection.Timestamp
        PID        = $Connection.PID
        Process    = $Connection.Process
        Protocol   = $Connection.Protocol
        RemoteIP   = $Connection.RemoteIP
        RemotePort = $Connection.RemotePort
        Hostname   = $Hostname
    })
}

# KORREKTUR: @() um den gesamten Filter-Ausdruck, um den StrictMode-Fehler bei null/leeren Arrays abzufangen
$ResolvedCount = @($Combined | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Hostname) }).Count
Write-Log "Hostname matches: $ResolvedCount"

Write-Host "`n===== COMBINED SAMPLE ====="
$Combined | Select-Object -First 20 Timestamp, RemoteIP, Hostname | Format-Table

Write-Host "`n===== DNS MAP SAMPLE ====="
$DnsMap.GetEnumerator() | Select-Object -First 20 | Format-Table

Write-Log "Generating reports"
Export-NetworkAnalysisReport `
    -OutputFolder $OutputFolder `
    -ProcessTree $AllProcessTree `
    -Connections $AllConnections `
    -DnsCache $AllDnsSnapshots `
    -DnsEvents $DnsEvents `
    -Combined $Combined `
    -Executable $Executable `
    -ReportVersion $ReportVersion
