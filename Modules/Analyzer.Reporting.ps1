Set-StrictMode -Version Latest

function Export-AnalyzerCsvReports {

    param(
        [string]$OutputFolder,
        [array]$ProcessTree,
        [array]$Connections,
        [array]$DnsCache,
        [array]$DnsEvents,
        [array]$Combined
    )

    $ProcessTree |
        Export-Csv `
        (Join-Path $OutputFolder "ProcessTree.csv") `
        -NoTypeInformation `
        -Encoding UTF8

    $Connections |
        Export-Csv `
        (Join-Path $OutputFolder "Connections.csv") `
        -NoTypeInformation `
        -Encoding UTF8

    $DnsCache |
        Export-Csv `
        (Join-Path $OutputFolder "DnsCache.csv") `
        -NoTypeInformation `
        -Encoding UTF8

    if($DnsEvents)
    {
        $DnsEvents |
            Export-Csv `
            (Join-Path $OutputFolder "DnsEvents.csv") `
            -NoTypeInformation `
            -Encoding UTF8
    }

    $Combined |
        Export-Csv `
        (Join-Path $OutputFolder "CombinedReport.csv") `
        -NoTypeInformation `
        -Encoding UTF8
}

function Get-HostStatistics {

    param(
        [array]$Combined
    )

    $Combined |
        Where-Object Hostname |
        Group-Object Hostname |
        Sort-Object Count -Descending |
        Select-Object `
            Name,
            Count
}

function Get-WildcardSuggestions {

    param(
        [string[]]$Hosts
    )

    $Domains = @()
    # Liste bekannter Second-Level-Domains für Ländercodes
    $KnownSLDs = @('co', 'com', 'net', 'org', 'gov', 'edu', 'ac', 'admin')

    foreach($Hostname in $Hosts)
    {
        $Parts = $Hostname.Split('.')

        if($Parts.Count -ge 2)
        {
            $tld = $Parts[-1]
            $sld = $Parts[-2]

            # Prüfung auf zusammengesetzte TLDs (z.B. .co.uk oder .admin.ch)
            if ($tld.Length -eq 2 -and $sld -in $KnownSLDs)
            {
                if ($Parts.Count -ge 4)
                {
                    # Beispiel: www.bbc.co.uk -> *.bbc.co.uk
                    $Domain = "*." + ($Parts[-3..-1] -join '.')
                }
                else
                {
                    # Beispiel: bbc.co.uk -> *.bbc.co.uk
                    $Domain = "*." + ($Parts -join '.') 
                }
            }
            else
            {
                # Standard-TLDs (z.B. .com, .ch, .de)
                if ($Parts.Count -ge 3)
                {
                    # Beispiel: api.google.com -> *.google.com
                    $Domain = "*." + ($Parts[-2..-1] -join '.')
                }
                else
                {
                    # Beispiel: google.com -> *.google.com
                    $Domain = "*." + ($Parts -join '.')
                }
            }

            $Domains += $Domain
        }
    }

    $Domains | Sort-Object -Unique
}

function Export-ProxyAllowList {

    param(
        [string]$OutputFolder,
        [array]$Combined
    )

    $Hosts =
        $Combined |
        Where-Object Hostname |
        Select-Object `
            -ExpandProperty Hostname `
            -Unique |
        Sort-Object

    $Hosts |
        Out-File `
        (Join-Path `
            $OutputFolder `
            "Proxy-AllowList.txt")

    $WildcardHosts =
        Get-WildcardSuggestions `
            -Hosts $Hosts

    $WildcardHosts |
        Out-File `
        (Join-Path `
            $OutputFolder `
            "Proxy-AllowList-Wildcards.txt")
}

function Get-Timeline {

    param(
        [array]$Combined
    )

    $Combined |
        Sort-Object Timestamp |
        Select-Object `
            Timestamp,
            Process,
            Hostname,
            RemoteIP,
            RemotePort
}

function New-HtmlReport {

    param(
        [string]$OutputFolder,
        [array]$Combined,
        [array]$ProcessTree,
        [string]$Executable,
        [string]$ReportVersion
    )

    $UniqueHosts = @(
        $Combined |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.Hostname)
        } |
        Select-Object `
            -ExpandProperty Hostname `
            -Unique
    ).Count

    $ConnectionCount = @($Combined).Count

    $UniqueProcesses = @(
        $ProcessTree |
        Select-Object -ExpandProperty ProcessId -Unique
    )

    $ProcessCount = $UniqueProcesses.Count

    $HostStats =
        Get-HostStatistics `
            -Combined $Combined

    $Timeline =
        Get-Timeline `
            -Combined $Combined

    $Html = @"

<html>
<head>
<title>Network Analysis Report</title>
<style>
body { font-family:Segoe UI; margin:20px; }
table { border-collapse:collapse; }
td,th { border:1px solid #ccc; padding:5px; }
th { background:#efefef; }
</style>
</head>
<body>
<h1>Network Analysis Report</h1>
<p>
<b>Executable:</b> $Executable
</p>
<p>
<b>Report Version:</b> $ReportVersion
</p>
<p>
<b>Generated:</b> $(Get-Date)
</p>
<h2>Summary</h2>
<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>Processes</td><td>$ProcessCount</td></tr>
<tr><td>Connections</td><td>$ConnectionCount</td></tr>
<tr><td>Unique Hosts</td><td>$UniqueHosts</td></tr>
</table>
<h2>Top Hosts</h2>
$(
$HostStats | ConvertTo-Html -Fragment
)
<h2>Timeline</h2>
$(
$Timeline | Select-Object -First 500 | ConvertTo-Html -Fragment
)
</body>
</html>

"@

    $Html |
        Out-File `
        (Join-Path $OutputFolder "Report.html") `
        -Encoding UTF8
}

function Export-NetworkAnalysisReport {

    param(
        [string]$OutputFolder,
        [array]$ProcessTree,
        [array]$Connections,
        [array]$DnsCache,
        [array]$DnsEvents,
        [array]$Combined,
        [string]$Executable,
        [string]$ReportVersion
    )

    Export-AnalyzerCsvReports `
        -OutputFolder $OutputFolder `
        -ProcessTree $ProcessTree `
        -Connections $Connections `
        -DnsCache $DnsCache `
        -DnsEvents $DnsEvents `
        -Combined $Combined

    Export-ProxyAllowList `
        -OutputFolder $OutputFolder `
        -Combined $Combined

New-HtmlReport `
    -OutputFolder $OutputFolder `
    -Combined $Combined `
    -ProcessTree $ProcessTree `
    -Executable $Executable `
    -ReportVersion $ReportVersion
}
