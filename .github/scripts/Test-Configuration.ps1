param([Parameter(Mandatory)][string]$ExpectedUrl)

$ErrorActionPreference = 'Stop'
foreach ($name in @('PP_ENVIRONMENT_URL', 'PP_APP_ID', 'PP_TENANT_ID', 'PP_CLIENT_SECRET')) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value) -or $value -match '(?i)placeholder|replace[_ -]?me|<|>') {
        throw "Missing or placeholder configuration: $name. See README.md."
    }
}
foreach ($name in @('PP_APP_ID', 'PP_TENANT_ID')) {
    $id = [guid]::Empty
    if (-not [guid]::TryParse([Environment]::GetEnvironmentVariable($name), [ref]$id) -or $id -eq [guid]::Empty) {
        throw "$name must be a non-empty GUID."
    }
}
if ($env:PP_ENVIRONMENT_URL.TrimEnd('/') -cne $ExpectedUrl) {
    throw 'Environment URL does not match the approved target.'
}
