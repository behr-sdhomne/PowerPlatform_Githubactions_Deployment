param(
    [Parameter(Mandatory)][string]$Managed,
    [Parameter(Mandatory)][string]$Unmanaged
)

$ErrorActionPreference = 'Stop'
$versions = @()
foreach ($package in @(@{ Path = $Managed; Flag = '1' }, @{ Path = $Unmanaged; Flag = '0' })) {
    $archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $package.Path))
    try {
        $entry = $archive.GetEntry('solution.xml')
        if ($null -eq $entry) { throw 'Package is missing solution.xml.' }
        $reader = [System.IO.StreamReader]::new($entry.Open())
        try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $archive.Dispose() }
    $manifest = $xml.ImportExportXml.SolutionManifest
    if ($manifest.UniqueName -cne 'BCURequestsWorkflow' -or $manifest.Managed -ne $package.Flag) {
        throw 'Solution name or managed/unmanaged package type is incorrect.'
    }
    if ($manifest.Version -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw 'Invalid solution version.' }
    $versions += [string]$manifest.Version
}
if ($versions[0] -ne $versions[1]) { throw 'Dev solution version changed between exports. Export again.' }
$versions[0]
