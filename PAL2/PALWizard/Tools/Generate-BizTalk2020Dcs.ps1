#requires -Version 3.0
[CmdletBinding()]
param()

Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$thresholdDir = Join-Path $root 'Thresholds'
$runtimeDir = Join-Path $root 'bin\Debug'

$bizTalkSource = Join-Path $runtimeDir 'BizTalkServer2006.xml'
$sqlSource = Join-Path $runtimeDir 'SQLServer2014.xml'
$osSource = Join-Path $runtimeDir 'QuickSystemOverview.xml'

function Get-CounterLogCounters {
    param(
        [string]$FilePath,
        [string[]]$IncludePrefixes
    )

    [xml]$doc = Get-Content -LiteralPath $FilePath
    $counters = New-Object System.Collections.Generic.List[string]

    foreach ($dataSource in $doc.SelectNodes('//DATASOURCE')) {
        if ([string]$dataSource.TYPE -ne 'CounterLog') {
            continue
        }

        $counterName = [string]$dataSource.NAME
        if ([string]::IsNullOrWhiteSpace($counterName)) {
            continue
        }

        if ($IncludePrefixes.Count -eq 0) {
            $counters.Add($counterName)
            continue
        }

        foreach ($prefix in $IncludePrefixes) {
            if ($counterName.StartsWith($prefix)) {
                $counters.Add($counterName)
                break
            }
        }
    }

    return @($counters | Sort-Object -Unique)
}

function Write-Dcs {
    param(
        [string]$OutPath,
        [string]$Name,
        [string]$Description,
        [string[]]$Counters
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$sb.AppendLine('<?Copyright (c) Microsoft Corporation. All rights reserved.?>')
    [void]$sb.AppendLine('<DataCollectorSet>')
    [void]$sb.AppendLine("<Name>$Name</Name>")
    [void]$sb.AppendLine("<Description>$Description</Description>")
    [void]$sb.AppendLine('<RootPath>%systemdrive%\perflogs\System\Performance</RootPath>')
    [void]$sb.AppendLine('<PerformanceCounterDataCollector>')
    [void]$sb.AppendLine("    <Name>$Name</Name>")
    [void]$sb.AppendLine('    <SampleInterval>15</SampleInterval>')

    foreach ($counter in $Counters) {
        $escaped = [System.Security.SecurityElement]::Escape($counter)
        [void]$sb.AppendLine("    <Counter>$escaped</Counter>")
    }

    [void]$sb.AppendLine('</PerformanceCounterDataCollector>')
    [void]$sb.AppendLine('</DataCollectorSet>')

    [System.IO.File]::WriteAllText($OutPath, $sb.ToString(), [System.Text.Encoding]::UTF8)
}

$osCounters = Get-CounterLogCounters -FilePath $osSource -IncludePrefixes @()
$bizTalkCounters = @(
    (Get-CounterLogCounters -FilePath $bizTalkSource -IncludePrefixes @('\BizTalk:', '\XLANG/s ')) +
    $osCounters
)
$sqlCounters = @(
    (Get-CounterLogCounters -FilePath $sqlSource -IncludePrefixes @('\SQLServer:', '\SQLAgent:')) +
    $osCounters
)

$bizTalkCounters = @($bizTalkCounters | Sort-Object -Unique)
$sqlCounters = @($sqlCounters | Sort-Object -Unique)

Write-Dcs -OutPath (Join-Path $thresholdDir 'BizTalkServer2020-BizTalk-DCS.xml') `
    -Name 'PAL_BizTalk_Server_2020_BizTalk_and_OS' `
    -Description 'BizTalk/XLANG plus OS counters for the BizTalk Server role. Generate from BizTalk and QuickSystemOverview threshold sources.' `
    -Counters $bizTalkCounters

Write-Dcs -OutPath (Join-Path $thresholdDir 'BizTalkServer2020-SQL-DCS.xml') `
    -Name 'PAL_BizTalk_Server_2020_SQL_and_OS' `
    -Description 'SQL/SQLAgent plus OS counters for SQL Server role. Use when BizTalk and SQL are split or combined.' `
    -Counters $sqlCounters

Write-Output "BizTalk counters: $($bizTalkCounters.Count)"
Write-Output "SQL counters: $($sqlCounters.Count)"
