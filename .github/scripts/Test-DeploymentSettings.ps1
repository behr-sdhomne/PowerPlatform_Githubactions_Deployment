param(
    [Parameter(Mandatory)][string]$Settings,
    [Parameter(Mandatory)][string]$ExpectedSolutionName,
    [Parameter(Mandatory)][ValidateSet('QA', 'Prod')][string]$ExpectedTarget,
    [string]$Solution,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\Test-SolutionName.ps1" -SolutionName $ExpectedSolutionName
$raw = Get-Content -LiteralPath $Settings -Raw
if ($raw -match '(?i)placeholder|replace[_ -]?me|<|>') {
    throw "Unresolved placeholder in $Settings."
}
$config = $raw | ConvertFrom-Json
if ($config.SolutionName -cne $ExpectedSolutionName -or $config.TargetEnvironment -cne $ExpectedTarget) {
    throw 'Deployment settings solution name or target environment does not match the selected release.'
}
if ('ConnectionReferences' -notin $config.PSObject.Properties.Name -or
    'EnvironmentVariables' -notin $config.PSObject.Properties.Name) {
    throw 'Deployment settings must contain ConnectionReferences and EnvironmentVariables arrays.'
}
foreach ($property in @('ConnectionReferences', 'EnvironmentVariables')) {
    if ($config.$property -isnot [array]) { throw "$property must be an array." }
}
if ($OutputPath -and -not $Solution) { throw 'A solution package is required to produce import settings.' }
$connectionNames = @()
$variableNames = @()
if ($Solution) {
    & "$PSScriptRoot\Test-SolutionPackages.ps1" -Managed $Solution -ExpectedSolutionName $ExpectedSolutionName | Out-Null
    $archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $Solution))
    try {
        $entry = $archive.GetEntry('customizations.xml')
        if ($null -eq $entry) { throw 'Solution is missing customizations.xml.' }
        $reader = [System.IO.StreamReader]::new($entry.Open())
        try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $archive.Dispose() }
    $connectionNames = @($xml.SelectNodes('//connectionreference') | ForEach-Object { $_.GetAttribute('connectionreferencelogicalname') })
    $variableNames = @($xml.SelectNodes('//environmentvariabledefinition') | ForEach-Object { $_.GetAttribute('schemaname') })
}

$seen = @{}
foreach ($reference in $config.ConnectionReferences) {
    if ([string]::IsNullOrWhiteSpace($reference.LogicalName) -or
        [string]::IsNullOrWhiteSpace($reference.ConnectionId) -or
        [string]::IsNullOrWhiteSpace($reference.ConnectorId)) {
        throw 'Each connection reference needs LogicalName, ConnectionId and ConnectorId.'
    }
    if ($seen.ContainsKey($reference.LogicalName)) { throw 'Duplicate connection reference.' }
    if ($Solution -and $reference.LogicalName -cnotin $connectionNames) {
        throw 'Connection mapping is not present in the selected solution.'
    }
    $seen[$reference.LogicalName] = $true
}
foreach ($name in $connectionNames) {
    if ([string]::IsNullOrWhiteSpace($name) -or -not $seen.ContainsKey($name)) {
        throw "Missing explicit target connection mapping: $name."
    }
}
$seen = @{}
foreach ($variable in $config.EnvironmentVariables) {
    if ([string]::IsNullOrWhiteSpace($variable.SchemaName) -or
        [string]::IsNullOrWhiteSpace([string]$variable.Value)) {
        throw 'Each environment variable needs SchemaName and a non-empty Value.'
    }
    if ($seen.ContainsKey($variable.SchemaName)) { throw 'Duplicate environment variable.' }
    if ($Solution -and $variable.SchemaName -cnotin $variableNames) {
        throw 'Environment variable mapping is not present in the selected solution.'
    }
    $seen[$variable.SchemaName] = $true
}
foreach ($name in $variableNames) {
    if ([string]::IsNullOrWhiteSpace($name) -or -not $seen.ContainsKey($name)) {
        throw "Missing explicit target environment variable: $name."
    }
}
if ($OutputPath) {
    @{
        EnvironmentVariables = $config.EnvironmentVariables
        ConnectionReferences = $config.ConnectionReferences
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath
}
Write-Output 'Deployment settings validation passed.'
