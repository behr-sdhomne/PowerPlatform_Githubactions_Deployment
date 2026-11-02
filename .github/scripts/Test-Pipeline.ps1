$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$count = 0
function Assert-Passes([string]$Name, [scriptblock]$Action) {
    & $Action | Out-Null
    $script:count++
    Write-Output "PASS $Name"
}
function Assert-Fails([string]$Name, [string]$Message, [scriptblock]$Action) {
    $failed = $false
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw }
        $failed = $true
    }
    if (-not $failed) { throw "$Name unexpectedly passed." }
    $script:count++
    Write-Output "PASS $Name"
}
function New-TestPackage([string]$Path, [string]$Customizations, [string]$Managed = '1', [string]$Version = '1.0.0.16') {
    $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $entries = @{
            'customizations.xml' = $Customizations
            'solution.xml' = "<ImportExportXml><SolutionManifest><UniqueName>BCURequestsWorkflow</UniqueName><Managed>$Managed</Managed><Version>$Version</Version></SolutionManifest></ImportExportXml>"
        }
        foreach ($name in $entries.Keys) {
            $writer = [IO.StreamWriter]::new($zip.CreateEntry($name).Open())
            try { $writer.Write($entries[$name]) } finally { $writer.Dispose() }
        }
    } finally { $zip.Dispose() }
}
$temp = Join-Path ([IO.Path]::GetTempPath()) "power-platform-tests-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $temp | Out-Null
$names = @('PP_ENVIRONMENT_URL', 'PP_APP_ID', 'PP_TENANT_ID', 'PP_CLIENT_SECRET', 'GH_TOKEN', 'GITHUB_API_URL', 'GITHUB_REPOSITORY')
$original = @{}
foreach ($name in $names) { $original[$name] = [Environment]::GetEnvironmentVariable($name) }
try {
    foreach ($file in Get-ChildItem $root -Filter '*.ps1') {
        $tokens = $null
        $errors = $null
        [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        if ($errors.Count) { throw ($errors | Out-String) }
    }
    Assert-Passes 'valid configuration' {
        $env:PP_ENVIRONMENT_URL = 'https://orgfd9b912f.crm.dynamics.com'
        $env:PP_APP_ID = [guid]::NewGuid().ToString()
        $env:PP_TENANT_ID = [guid]::NewGuid().ToString()
        $env:PP_CLIENT_SECRET = 'synthetic-test-value-not-a-credential'
        & "$root\Test-Configuration.ps1" -ExpectedUrl $env:PP_ENVIRONMENT_URL
    }
    Assert-Fails 'wrong target URL' 'does not match' {
        & "$root\Test-Configuration.ps1" -ExpectedUrl 'https://wrong.crm.dynamics.com'
    }
    Assert-Fails 'missing secret' 'Missing or placeholder' {
        $env:PP_CLIENT_SECRET = ''
        & "$root\Test-Configuration.ps1" -ExpectedUrl $env:PP_ENVIRONMENT_URL
    }
    Assert-Fails 'placeholder secret' 'Missing or placeholder' {
        $env:PP_CLIENT_SECRET = 'REPLACE_ME'
        & "$root\Test-Configuration.ps1" -ExpectedUrl $env:PP_ENVIRONMENT_URL
    }
    $env:PP_CLIENT_SECRET = 'synthetic-test-value-not-a-credential'
    Assert-Fails 'invalid client ID' 'non-empty GUID' {
        $env:PP_APP_ID = 'not-an-id'
        & "$root\Test-Configuration.ps1" -ExpectedUrl $env:PP_ENVIRONMENT_URL
    }
    Assert-Fails 'zero tenant ID' 'non-empty GUID' {
        $env:PP_APP_ID = [guid]::NewGuid().ToString()
        $env:PP_TENANT_ID = [guid]::Empty.ToString()
        & "$root\Test-Configuration.ps1" -ExpectedUrl $env:PP_ENVIRONMENT_URL
    }

    $empty = Join-Path $temp 'empty.zip'
    $mapped = Join-Path $temp 'mapped.zip'
    $unmanaged = Join-Path $temp 'unmanaged.zip'
    $otherVersion = Join-Path $temp 'other-version.zip'
    $settings = Join-Path $temp 'settings.json'
    New-TestPackage $empty '<ImportExportXml />'
    New-TestPackage $unmanaged '<ImportExportXml />' '0'
    New-TestPackage $otherVersion '<ImportExportXml />' '0' '1.0.0.17'
    New-TestPackage $mapped '<ImportExportXml><connectionreferences><connectionreference connectionreferencelogicalname="behr_shared" /></connectionreferences><environmentvariabledefinitions><environmentvariabledefinition schemaname="behr_url" /></environmentvariabledefinitions></ImportExportXml>'
    '{"EnvironmentVariables":[],"ConnectionReferences":[]}' | Set-Content $settings
    Assert-Passes 'empty settings for package without references' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $empty -Settings $settings
    }
    Assert-Fails 'missing connection mapping' 'Missing explicit target connection' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $mapped -Settings $settings
    }
    $config = @{
        EnvironmentVariables = @(@{ SchemaName = 'behr_url'; Value = 'https://qa.example.test' })
        ConnectionReferences = @(@{ LogicalName = 'behr_shared'; ConnectionId = 'synthetic-test-connection'; ConnectorId = 'synthetic-test-connector' })
    }
    $config | ConvertTo-Json -Depth 5 | Set-Content $settings
    Assert-Passes 'complete target settings' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $mapped -Settings $settings
    }
    $config.EnvironmentVariables = @()
    $config | ConvertTo-Json -Depth 5 | Set-Content $settings
    Assert-Fails 'missing environment variable' 'Missing explicit target environment variable' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $mapped -Settings $settings
    }
    $config.EnvironmentVariables = @(@{ SchemaName = 'behr_url'; Value = 'REPLACE_ME' })
    $config | ConvertTo-Json -Depth 5 | Set-Content $settings
    Assert-Fails 'unresolved settings placeholder' 'Unresolved placeholder' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $mapped -Settings $settings
    }
    $config.EnvironmentVariables = @(@{ SchemaName = 'behr_url'; Value = '' })
    $config | ConvertTo-Json -Depth 5 | Set-Content $settings
    Assert-Fails 'blank environment value' 'non-empty Value' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $mapped -Settings $settings
    }
    $config.EnvironmentVariables = @(@{ SchemaName = 'behr_url'; Value = 'qa' })
    $config.ConnectionReferences += $config.ConnectionReferences[0]
    $config | ConvertTo-Json -Depth 5 | Set-Content $settings
    Assert-Fails 'duplicate connection' 'Duplicate connection reference' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $mapped -Settings $settings
    }
    Assert-Passes 'matching package identity' {
        & "$root\Test-SolutionPackages.ps1" -Managed $empty -Unmanaged $unmanaged
    }
    Assert-Fails 'wrong managed package type' 'package type is incorrect' {
        & "$root\Test-SolutionPackages.ps1" -Managed $unmanaged -Unmanaged $empty
    }
    Assert-Fails 'version changed between exports' 'changed between exports' {
        & "$root\Test-SolutionPackages.ps1" -Managed $empty -Unmanaged $otherVersion
    }

    function Invoke-RestMethod {
        param($Uri, $Headers)
        if ($Uri -like '*deployment-branch-policies*') { return $testGatePolicy }
        return $testGateProtection
    }
    $testGateProtection = @{
        can_admins_bypass = $false
        protection_rules = @([pscustomobject]@{ type = 'required_reviewers'; reviewers = @(@{ reviewer = @{ login = 'behr-sdhomne' } }) })
        deployment_branch_policy = @{ custom_branch_policies = $true }
    }
    $testGatePolicy = @{ total_count = 1; branch_policies = @(@{ name = 'main'; type = 'branch' }) }
    Assert-Passes 'configured production gate' { & "$root\Test-ProductionGate.ps1" }
    $testGateProtection.can_admins_bypass = $true
    Assert-Fails 'administrator bypass enabled' 'disable administrator bypass' { & "$root\Test-ProductionGate.ps1" }
    $testGateProtection.can_admins_bypass = $false
    $testGateProtection.protection_rules = @()
    Assert-Fails 'absent required reviewer' 'must require approval' { & "$root\Test-ProductionGate.ps1" }
    $testGateProtection.protection_rules = @([pscustomobject]@{ type = 'required_reviewers'; reviewers = @(@{ reviewer = @{ login = 'behr-sdhomne' } }) })
    $testGatePolicy.branch_policies[0].name = '*'
    Assert-Fails 'overbroad production branch rule' 'exactly the main branch' { & "$root\Test-ProductionGate.ps1" }
    $testGatePolicy.branch_policies[0].name = 'main'
    $testGatePolicy.branch_policies[0].type = 'tag'
    Assert-Fails 'main tag is not main branch' 'exactly the main branch' { & "$root\Test-ProductionGate.ps1" }
    Write-Output "$count guard tests passed; all PowerShell scripts parsed."
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $original[$name]) }
    Remove-Item -LiteralPath $temp -Recurse -Force
}
