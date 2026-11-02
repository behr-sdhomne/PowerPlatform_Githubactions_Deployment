param(
    [Parameter(Mandatory)][string]$Solution,
    [Parameter(Mandatory)][string]$Settings
)

$ErrorActionPreference = 'Stop'
$raw = Get-Content -LiteralPath $Settings -Raw
if ($raw -match '(?i)placeholder|replace[_ -]?me|<|>') {
    throw "Unresolved placeholder in $Settings."
}
$config = $raw | ConvertFrom-Json
if ('ConnectionReferences' -notin $config.PSObject.Properties.Name -or
    'EnvironmentVariables' -notin $config.PSObject.Properties.Name) {
    throw 'Deployment settings must contain ConnectionReferences and EnvironmentVariables arrays.'
}
foreach ($property in @('ConnectionReferences', 'EnvironmentVariables')) {
    if ($config.$property -isnot [array]) { throw "$property must be an array." }
}
$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $Solution))
try {
    $entry = $archive.GetEntry('customizations.xml')
    if ($null -eq $entry) { throw 'Solution is missing customizations.xml.' }
    $reader = [System.IO.StreamReader]::new($entry.Open())
    try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
} finally { $archive.Dispose() }

$seen = @{}
foreach ($reference in $config.ConnectionReferences) {
    if ([string]::IsNullOrWhiteSpace($reference.LogicalName) -or
        [string]::IsNullOrWhiteSpace($reference.ConnectionId) -or
        [string]::IsNullOrWhiteSpace($reference.ConnectorId)) {
        throw 'Each connection reference needs LogicalName, ConnectionId and ConnectorId.'
    }
    if ($seen.ContainsKey($reference.LogicalName)) { throw 'Duplicate connection reference.' }
    $seen[$reference.LogicalName] = $true
}
foreach ($node in $xml.SelectNodes('//connectionreference')) {
    $name = $node.GetAttribute('connectionreferencelogicalname')
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
    $seen[$variable.SchemaName] = $true
}
foreach ($node in $xml.SelectNodes('//environmentvariabledefinition')) {
    $name = $node.GetAttribute('schemaname')
    if ([string]::IsNullOrWhiteSpace($name) -or -not $seen.ContainsKey($name)) {
        throw "Missing explicit target environment variable: $name."
    }
}
Write-Output 'Deployment settings contain explicit mappings for all packaged references and variables.'
