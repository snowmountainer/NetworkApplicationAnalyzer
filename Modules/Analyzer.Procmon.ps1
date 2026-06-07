Set-StrictMode -Version Latest

function Start-Procmon {
    param(
        [string]$ProcmonPath,
        [string]$PmlFile
    )

    Write-Log "Starting Procmon"

    $ProcmonArgs = @(
        "/AcceptEula",
        "/Quiet",
        "/BackingFile",
        "`"$PmlFile`""
    )

    Start-Process -FilePath $ProcmonPath -ArgumentList $ProcmonArgs
    Start-Sleep -Seconds 3
}

function Stop-Procmon {
    param(
        [string]$ProcmonPath,
        [string]$PmlFile,
        [string]$CsvFile
    )

    Write-Log "Stopping Procmon"
    & $ProcmonPath /Terminate

    Start-Sleep -Seconds 5

    if (Test-Path $PmlFile) {
        & $ProcmonPath /OpenLog "`"$PmlFile`"" /SaveAs "`"$CsvFile`""
    }
}