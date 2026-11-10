param(
    [Parameter(Mandatory)][string]$Solution,
    [Parameter(Mandatory)][string]$ExpectedSolutionName,
    [Parameter(Mandatory)][ValidateSet('QA', 'Prod')][string]$ExpectedTarget,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\Test-SolutionName.ps1" -SolutionName $ExpectedSolutionName

function Protect-LogValue([string]$Value) {
    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $escaped = $Value.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
        Write-Output "::add-mask::$escaped"
    }
}

function Protect-LogTree($Value) {
    if ($Value -is [string]) {
        Protect-LogValue $Value
    } elseif ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) {
            Protect-LogValue $property.Name
            Protect-LogTree $property.Value
        }
    } elseif ($Value -is [array]) {
        foreach ($item in $Value) { Protect-LogTree $item }
    }
}

try {
    $raw = $env:PP_DEPLOYMENT_SETTINGS_JSON
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw 'Missing private settings.'
    }
    Protect-LogValue $raw
    $configuration = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
    Protect-LogTree $configuration
    if ($configuration -isnot [pscustomobject]) { throw 'Settings must be a JSON object.' }
    $allowed = @('SolutionName', 'TargetEnvironment', 'EnvironmentVariables', 'ConnectionReferences')
    if (@($configuration.PSObject.Properties.Name | Where-Object { $_ -cnotin $allowed }).Count) {
        throw 'Unknown private settings property.'
    }
    foreach ($entry in $configuration.EnvironmentVariables) {
        if ($entry -isnot [pscustomobject] -or $entry.SchemaName -isnot [string] -or $entry.Value -isnot [string] -or
            @($entry.PSObject.Properties.Name | Where-Object { $_ -cnotin @('SchemaName', 'Value') }).Count) {
            throw 'Invalid private environment variable entry.'
        }
    }
    foreach ($entry in $configuration.ConnectionReferences) {
        if ($entry -isnot [pscustomobject] -or $entry.LogicalName -isnot [string] -or
            $entry.ConnectionId -isnot [string] -or $entry.ConnectorId -isnot [string] -or
            @($entry.PSObject.Properties.Name | Where-Object { $_ -cnotin @('LogicalName', 'ConnectionId', 'ConnectorId') }).Count) {
            throw 'Invalid private connection reference entry.'
        }
    }
    & "$PSScriptRoot\Test-DeploymentSettings.ps1" -Configuration $configuration `
        -Solution $Solution -ExpectedSolutionName $ExpectedSolutionName -ExpectedTarget $ExpectedTarget `
        -OutputPath $OutputPath | Out-Null
} catch {
    # Never surface parser or validation exceptions containing private JSON.
    if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }
    throw 'Private deployment settings are missing or invalid. Check the selected environment secret, solution/target identity, JSON schema and complete package inventory.'
} finally {
    $env:PP_DEPLOYMENT_SETTINGS_JSON = $null
}
Write-Output 'Private deployment settings validated and prepared for import.'
