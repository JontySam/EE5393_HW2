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
$reactions = Join-Path $scriptDir 'q1_fibonacci.r'

$species = @()
0..12 | ForEach-Object {
    $species += "A$_"
    $species += "B$_"
}

$cases = @(
    @{
        Name = 'q1_case_01'
        State = 'q1_case_01.in'
        ExpectedA12 = 144
        ExpectedB12 = 233
    },
    @{
        Name = 'q1_case_37'
        State = 'q1_case_37.in'
        ExpectedA12 = 1275
        ExpectedB12 = 2063
    }
)

$summaryLines = @(
    'Q1 Fibonacci verification',
    'A_k is the first Fibonacci state after k steps; B_k is the second.',
    ''
)

foreach ($case in $cases) {
    $stateFile = Join-Path $scriptDir $case.State
    $rawOutput = & $aleae $stateFile $reactions 1 -1 0 | Out-String
    $rawPath = Join-Path $resultsDir "$($case.Name)_raw.txt"
    Set-Content -Path $rawPath -Value $rawOutput -Encoding ascii

    $values = Get-AleaeAverageVector -Text $rawOutput
    if ($values.Count -ne $species.Count) {
        throw "Expected $($species.Count) state values but found $($values.Count)."
    }

    $stateMap = @{}
    for ($i = 0; $i -lt $species.Count; $i++) {
        $stateMap[$species[$i]] = [long][math]::Round($values[$i])
    }

    $a12 = $stateMap['A12']
    $b12 = $stateMap['B12']

    if ($a12 -ne $case.ExpectedA12 -or $b12 -ne $case.ExpectedB12) {
        throw "$($case.Name) failed: expected (A12,B12)=($($case.ExpectedA12),$($case.ExpectedB12)) but saw ($a12,$b12)."
    }

    $summaryLines += "$($case.Name): A12=$a12, B12=$b12"
}

$summaryPath = Join-Path $resultsDir 'q1_summary.txt'
Set-Content -Path $summaryPath -Value $summaryLines -Encoding ascii
$summaryLines | ForEach-Object { Write-Host $_ }
