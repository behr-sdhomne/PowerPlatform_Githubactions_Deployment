param(
    [Parameter(Mandatory)][string]$ReleaseDirectory,
    [Parameter(Mandatory)][string]$ExpectedSolutionName,
    [Parameter(Mandatory)][string]$ExpectedSha256,
    [Parameter(Mandatory)][string]$ExpectedSourceCommit
)

$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\Test-SolutionName.ps1" -SolutionName $ExpectedSolutionName
$package = Join-Path $ReleaseDirectory 'managed.zip'
$actual = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash
if ($ExpectedSha256 -notmatch '\A[A-Fa-f0-9]{64}\z' -or $actual -ne $ExpectedSha256) {
    throw 'Managed solution digest does not match the checked Dev export.'
}
$version = & "$PSScriptRoot\Test-SolutionPackages.ps1" -Managed $package -ExpectedSolutionName $ExpectedSolutionName
$manifest = Get-Content -LiteralPath (Join-Path $ReleaseDirectory 'manifest.json') -Raw | ConvertFrom-Json
if ($manifest.solution -cne $ExpectedSolutionName -or $manifest.managedSha256 -ne $actual -or
    $manifest.sourceCommit -cne $ExpectedSourceCommit -or $manifest.version -cne $version) {
    throw 'Release manifest does not match the selected solution, digest, source commit or package version.'
}
Write-Output 'Managed release identity and digest verified.'
