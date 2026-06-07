Set-StrictMode -Version Latest

function Initialize-Logging {
    param(
        [string]$OutputFolder
    )

    $Global:LogFile = Join-Path $OutputFolder "Analyzer.log"
    Start-Transcript -Path (Join-Path $OutputFolder "Transcript.log") -Force
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","DEBUG")]
        [string]$Level = "INFO"
    )

    $Line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message

    Write-Host $Line
    Add-Content -Path $Global:LogFile -Value $Line
}

function Write-Exception {
    param(
        $ErrorRecord
    )

    Write-Log -Level ERROR -Message $ErrorRecord.Exception.Message

    if ($ErrorRecord.ScriptStackTrace) {
        Write-Log -Level ERROR -Message $ErrorRecord.ScriptStackTrace
    }
}