$ErrorActionPreference = 'Stop'

function Get-AleaeAverageVector {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $match = [regex]::Match($Text, '(?m)^avg \[(.+?)\]\r?$')
    if (-not $match.Success) {
        throw 'Could not find the average-state line in Aleae output.'
    }

    return $match.Groups[1].Value.Split(',') | ForEach-Object {
        [double]($_.Trim())
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$resultsDir = Join-Path $scriptDir 'results'
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$aleae = Join-Path $scriptDir 'aleae.exe'
$reactions = Join-Path $scriptDir 'q2_biquad_cycle.r'

$signalScale = 8192L
$inputs = @(100L, 5L, 500L, 20L, 250L)
$species = @('X', 'B1', 'B2', 'Xfb', 'B1_next', 'B2_next', 'Y')

$b1 = 0L
$b2 = 0L
$rows = @()

for ($cycle = 1; $cycle -le $inputs.Count; $cycle++) {
    $inputValue = $inputs[$cycle - 1]
    $x = $inputValue * $signalScale

    $statePath = Join-Path $resultsDir ("q2_cycle_{0}.in" -f $cycle)
    $stateLines = @(
        "X $x N",
        "B1 $b1 N",
        "B2 $b2 N",
        'Xfb 0 N',
        'B1_next 0 N',
        'B2_next 0 N',
        'Y 0 N'
    )
    Set-Content -Path $statePath -Value $stateLines -Encoding ascii

    $rawOutput = & $aleae $statePath $reactions 1 -1 0 | Out-String
    $rawPath = Join-Path $resultsDir ("q2_cycle_{0}_raw.txt" -f $cycle)
    Set-Content -Path $rawPath -Value $rawOutput -Encoding ascii

    $values = Get-AleaeAverageVector -Text $rawOutput
    if ($values.Count -ne $species.Count) {
        throw "Expected $($species.Count) state values but found $($values.Count)."
    }

    $stateMap = @{}
    for ($i = 0; $i -lt $species.Count; $i++) {
        $stateMap[$species[$i]] = [long][math]::Round($values[$i])
    }

    $expectedXfb = ($b1 / 8L) + ($b2 / 8L)
    $expectedB1Next = $x + $expectedXfb
    $expectedB2Next = $b1
    $expectedY = ($x / 8L) + ($b1 / 8L) + ($b2 / 8L) + ($expectedXfb / 8L)

    if ($stateMap['X'] -ne 0L -or $stateMap['B1'] -ne 0L -or $stateMap['B2'] -ne 0L -or $stateMap['Xfb'] -ne 0L) {
        throw "Cycle $cycle did not fully drain the transient species."
    }
    if ($stateMap['B1_next'] -ne $expectedB1Next -or $stateMap['B2_next'] -ne $expectedB2Next -or $stateMap['Y'] -ne $expectedY) {
        throw "Cycle $cycle failed the expected recurrence check."
    }

    $rows += [pscustomobject]@{
        Cycle = $cycle
        Input = $inputValue
        Output_Count = $stateMap['Y']
        Output_Signal = [double]$stateMap['Y'] / [double]$signalScale
        Next_B1_Count = $stateMap['B1_next']
        Next_B1_Signal = [double]$stateMap['B1_next'] / [double]$signalScale
        Next_B2_Count = $stateMap['B2_next']
        Next_B2_Signal = [double]$stateMap['B2_next'] / [double]$signalScale
    }

    $b1 = $stateMap['B1_next']
    $b2 = $stateMap['B2_next']
}

$csvPath = Join-Path $resultsDir 'q2_biquad_results.csv'
$rows | Export-Csv -Path $csvPath -NoTypeInformation

$summaryLines = @(
    'Q2 biquad verification',
    "Signal scale: $signalScale molecules per signal unit",
    'Cycle Input Output_Signal Next_B1_Signal Next_B2_Signal'
)
foreach ($row in $rows) {
    $summaryLines += ('{0,5} {1,5} {2,13:F12} {3,14:F12} {4,14:F12}' -f $row.Cycle, $row.Input, $row.Output_Signal, $row.Next_B1_Signal, $row.Next_B2_Signal)
}

$summaryPath = Join-Path $resultsDir 'q2_summary.txt'
Set-Content -Path $summaryPath -Value $summaryLines -Encoding ascii
$summaryLines | ForEach-Object { Write-Host $_ }
