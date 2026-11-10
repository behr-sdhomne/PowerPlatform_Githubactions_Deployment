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
function New-TestPackage([string]$Path, [string]$Customizations, [string]$Managed = '1', [string]$Version = '1.0.0.16', [string]$SolutionName = 'GithubSolutions_POC') {
    $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $entries = @{
            'customizations.xml' = $Customizations
            'solution.xml' = "<ImportExportXml><SolutionManifest><UniqueName>$SolutionName</UniqueName><Managed>$Managed</Managed><Version>$Version</Version></SolutionManifest></ImportExportXml>"
        }
        foreach ($name in $entries.Keys) {
            $writer = [IO.StreamWriter]::new($zip.CreateEntry($name).Open())
            try { $writer.Write($entries[$name]) } finally { $writer.Dispose() }
        }
    } finally { $zip.Dispose() }
}
$temp = Join-Path ([IO.Path]::GetTempPath()) "power-platform-tests-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $temp | Out-Null
$names = @('PP_ENVIRONMENT_URL', 'PP_APP_ID', 'PP_TENANT_ID', 'PP_CLIENT_SECRET', 'GH_TOKEN', 'GITHUB_API_URL', 'GITHUB_REPOSITORY', 'PP_DEPLOYMENT_SETTINGS_JSON')
$original = @{}
foreach ($name in $names) { $original[$name] = [Environment]::GetEnvironmentVariable($name) }
try {
    foreach ($file in Get-ChildItem $root -Filter '*.ps1') {
        $tokens = $null
        $errors = $null
        [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        if ($errors.Count) { throw ($errors | Out-String) }
    }
    foreach ($valid in @('GithubSolutions_POC', 'BCURequestsWorkflow', 'AnotherSolution123', ('A' * 65))) {
        Assert-Passes "solution name $valid" {
            & "$root\Test-SolutionName.ps1" -SolutionName $valid
        }
    }
    foreach ($invalid in @('../Other', '..\Other', 'A/B', 'A\B', ' A', 'A ', "A`n", 'A;whoami', '$(whoami)', 'A"b', 'A:b', 'A*', '1Solution', ('A' * 66), 'CON', 'nul', 'COM1')) {
        Assert-Fails "unsafe solution name [$invalid]" 'Solution unique name must' {
            & "$root\Test-SolutionName.ps1" -SolutionName $invalid
        }
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
    $settingsArgs = @{ ExpectedSolutionName = 'GithubSolutions_POC'; ExpectedTarget = 'QA' }
    New-TestPackage $empty '<ImportExportXml />'
    New-TestPackage $unmanaged '<ImportExportXml />' '0'
    New-TestPackage $otherVersion '<ImportExportXml />' '0' '1.0.0.17'
    New-TestPackage $mapped '<ImportExportXml><connectionreferences><connectionreference connectionreferencelogicalname="behr_shared" /></connectionreferences><environmentvariabledefinitions><environmentvariabledefinition schemaname="behr_url" /></environmentvariabledefinitions></ImportExportXml>'
    '{"SolutionName":"GithubSolutions_POC","TargetEnvironment":"QA","EnvironmentVariables":[],"ConnectionReferences":[]}' | Set-Content $settings
    Assert-Passes 'settings preflight without package' {
        & "$root\Test-DeploymentSettings.ps1" -Settings $settings @settingsArgs
    }
    Assert-Fails 'missing per-solution file' 'does not exist' {
        & "$root\Test-DeploymentSettings.ps1" -Settings (Join-Path $temp 'missing.json') @settingsArgs
    }
    Assert-Passes 'empty settings for package without references' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $empty -Settings $settings @settingsArgs
    }
    Assert-Fails 'missing connection mapping' 'Missing explicit target connection' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $mapped -Settings $settings @settingsArgs
    }
    $config = @{
        SolutionName = 'GithubSolutions_POC'
        TargetEnvironment = 'QA'
        EnvironmentVariables = @(@{ SchemaName = 'behr_url'; Value = 'https://qa.example.test' })
        ConnectionReferences = @(@{ LogicalName = 'behr_shared'; ConnectionId = 'synthetic-test-connection'; ConnectorId = 'synthetic-test-connector' })
    }
    $config | ConvertTo-Json -Depth 5 | Set-Content $settings
    Assert-Passes 'complete target settings' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $mapped -Settings $settings @settingsArgs
    }
    Assert-Fails 'settings from a different solution' 'does not match the selected release' {
        & "$root\Test-DeploymentSettings.ps1" -Settings $settings -ExpectedSolutionName BCURequestsWorkflow -ExpectedTarget QA
    }
    Assert-Fails 'QA settings copied to Prod' 'does not match the selected release' {
        & "$root\Test-DeploymentSettings.ps1" -Settings $settings -ExpectedSolutionName GithubSolutions_POC -ExpectedTarget Prod
    }
    $output = Join-Path $temp 'import-settings.json'
    Assert-Passes 'render PAC-only import settings' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $mapped -Settings $settings -OutputPath $output @settingsArgs
        $rendered = Get-Content $output -Raw | ConvertFrom-Json
        if ($rendered.PSObject.Properties.Name.Count -ne 2 -or
            'SolutionName' -in $rendered.PSObject.Properties.Name -or
            $rendered.ConnectionReferences[0].LogicalName -ne 'behr_shared') {
            throw 'Unexpected rendered PAC settings.'
        }
    }
    Assert-Fails 'refuse output without package validation' 'solution package is required' {
        & "$root\Test-DeploymentSettings.ps1" -Settings $settings -OutputPath $output @settingsArgs
    }
    $config.EnvironmentVariables += @{ SchemaName = 'other_solution_variable'; Value = 'qa' }
    $config | ConvertTo-Json -Depth 5 | Set-Content $settings
    Assert-Fails 'unrelated environment variable rejected' 'not present in the selected solution' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $mapped -Settings $settings @settingsArgs
    }
    $config.EnvironmentVariables = @(@{ SchemaName = 'behr_url'; Value = 'qa' })
    $config.ConnectionReferences += @{ LogicalName = 'other_solution_connection'; ConnectionId = 'synthetic'; ConnectorId = 'synthetic' }
    $config | ConvertTo-Json -Depth 5 | Set-Content $settings
    Assert-Fails 'unrelated connection mapping rejected' 'not present in the selected solution' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $mapped -Settings $settings @settingsArgs
    }
    $config.ConnectionReferences = @($config.ConnectionReferences[0])
    $config.EnvironmentVariables = @()
    $config | ConvertTo-Json -Depth 5 | Set-Content $settings
    Assert-Fails 'missing environment variable' 'Missing explicit target environment variable' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $mapped -Settings $settings @settingsArgs
    }
    $config.EnvironmentVariables = @(@{ SchemaName = 'behr_url'; Value = 'REPLACE_ME' })
    $config | ConvertTo-Json -Depth 5 | Set-Content $settings
    Assert-Fails 'unresolved settings placeholder' 'Unresolved placeholder' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $mapped -Settings $settings @settingsArgs
    }
    $config.EnvironmentVariables = @(@{ SchemaName = 'behr_url'; Value = '' })
    $config | ConvertTo-Json -Depth 5 | Set-Content $settings
    Assert-Fails 'blank environment value' 'non-empty Value' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $mapped -Settings $settings @settingsArgs
    }
    $config.EnvironmentVariables = @(@{ SchemaName = 'behr_url'; Value = 'qa' })
    $config.ConnectionReferences += $config.ConnectionReferences[0]
    $config | ConvertTo-Json -Depth 5 | Set-Content $settings
    Assert-Fails 'duplicate connection' 'Duplicate connection reference' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $mapped -Settings $settings @settingsArgs
    }
    Assert-Passes 'matching package identity' {
        & "$root\Test-SolutionPackages.ps1" -Managed $empty -Unmanaged $unmanaged -ExpectedSolutionName GithubSolutions_POC
    }
    Assert-Fails 'wrong managed package type' 'package type is incorrect' {
        & "$root\Test-SolutionPackages.ps1" -Managed $unmanaged -Unmanaged $empty -ExpectedSolutionName GithubSolutions_POC
    }
    Assert-Fails 'version changed between exports' 'changed between exports' {
        & "$root\Test-SolutionPackages.ps1" -Managed $empty -Unmanaged $otherVersion -ExpectedSolutionName GithubSolutions_POC
    }
    Assert-Fails 'package belonging to a different solution' 'package type is incorrect' {
        & "$root\Test-SolutionPackages.ps1" -Managed $empty -ExpectedSolutionName BCURequestsWorkflow
    }
    Assert-Fails 'settings cannot validate wrong solution package' 'package type is incorrect' {
        @{ SolutionName = 'BCURequestsWorkflow'; TargetEnvironment = 'QA'; EnvironmentVariables = @(); ConnectionReferences = @() } |
            ConvertTo-Json | Set-Content $settings
        & "$root\Test-DeploymentSettings.ps1" -Solution $empty `
            -Settings $settings `
            -ExpectedSolutionName BCURequestsWorkflow -ExpectedTarget QA
    }
    $bcuManaged = Join-Path $temp 'bcu-managed.zip'
    $bcuUnmanaged = Join-Path $temp 'bcu-unmanaged.zip'
    New-TestPackage $bcuManaged '<ImportExportXml />' -SolutionName BCURequestsWorkflow
    New-TestPackage $bcuUnmanaged '<ImportExportXml />' '0' -SolutionName BCURequestsWorkflow
    Assert-Passes 'BCU package identity remains supported' {
        & "$root\Test-SolutionPackages.ps1" -Managed $bcuManaged -Unmanaged $bcuUnmanaged -ExpectedSolutionName BCURequestsWorkflow
    }
    foreach ($target in @('QA', 'Prod')) {
        Assert-Passes "BCU settings identity $target" {
            @{ SolutionName = 'BCURequestsWorkflow'; TargetEnvironment = $target; EnvironmentVariables = @(); ConnectionReferences = @() } |
                ConvertTo-Json | Set-Content $settings
            & "$root\Test-DeploymentSettings.ps1" -Solution $bcuManaged `
                -Settings $settings `
                -ExpectedSolutionName BCURequestsWorkflow -ExpectedTarget $target
        }
    }
    $poc = Join-Path $temp 'poc.zip'
    $variablesXml = (1..4 | ForEach-Object { "<environmentvariabledefinition schemaname=`"synthetic_poc_$_`" />" }) -join ''
    New-TestPackage $poc "<ImportExportXml><connectionreferences><connectionreference connectionreferencelogicalname=`"behr_shared`" /></connectionreferences><environmentvariabledefinitions>$variablesXml</environmentvariabledefinitions></ImportExportXml>"
    $config.ConnectionReferences = @($config.ConnectionReferences[0])
    $config.EnvironmentVariables = @(1..4 | ForEach-Object { @{ SchemaName = "synthetic_poc_$_"; Value = "synthetic-target-value-$_" } })
    $config | ConvertTo-Json -Depth 5 | Set-Content $settings
    Assert-Passes 'POC-shaped synthetic inventory: one reference and four variables' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $poc -Settings $settings @settingsArgs
    }
    $config.EnvironmentVariables = @($config.EnvironmentVariables | Select-Object -First 3)
    $config | ConvertTo-Json -Depth 5 | Set-Content $settings
    Assert-Fails 'POC-shaped inventory missing fourth variable' 'Missing explicit target environment variable' {
        & "$root\Test-DeploymentSettings.ps1" -Solution $poc -Settings $settings @settingsArgs
    }

    $privatePath = Join-Path $temp 'private-settings.json'
    $privateArgs = @{
        Solution = $poc
        ExpectedSolutionName = 'GithubSolutions_POC'
        ExpectedTarget = 'QA'
        OutputPath = $privatePath
    }
    $config.EnvironmentVariables = @(1..4 | ForEach-Object { @{ SchemaName = "synthetic_poc_$_"; Value = "synthetic-target-value-$_" } })
    $privateJson = $config | ConvertTo-Json -Depth 5
    Assert-Passes 'private JSON renders only PAC arrays and masks each value' {
        $env:PP_DEPLOYMENT_SETTINGS_JSON = $privateJson
        $messages = @(& "$root\New-PrivateDeploymentSettings.ps1" @privateArgs)
        $rendered = Get-Content $privatePath -Raw | ConvertFrom-Json
        if ($rendered.EnvironmentVariables.Count -ne 4 -or $rendered.ConnectionReferences.Count -ne 1 -or
            @($rendered.PSObject.Properties.Name).Count -ne 2) { throw 'Private output schema mismatch.' }
        foreach ($value in @('synthetic-target-value-1', 'synthetic-target-value-4', 'behr_shared', 'synthetic-test-connection')) {
            if ("::add-mask::$value" -notin $messages) { throw 'Private value was not masked.' }
        }
        if (@($messages | Where-Object { $_ -notlike '::add-mask::*' -and $_ -ne 'Private deployment settings validated and prepared for import.' }).Count) {
            throw 'Unexpected private settings log output.'
        }
        if ($env:PP_DEPLOYMENT_SETTINGS_JSON) { throw 'Private JSON remained in the process environment.' }
    }
    foreach ($case in @('absent', 'malformed', 'wrong-solution', 'wrong-target', 'missing-variable', 'extra-variable', 'missing-connection',
        'unknown-property', 'non-string-value', 'placeholder', 'missing-array', 'non-array', 'duplicate-variable',
        'duplicate-connection', 'unknown-entry-property', 'empty-value', 'array-root', 'null-root')) {
        Assert-Passes "private config rejects $case with sanitized error and removes stale file" {
            $candidate = $privateJson | ConvertFrom-Json
            switch ($case) {
                'wrong-solution' { $candidate.SolutionName = 'AnotherSolution' }
                'wrong-target' { $candidate.TargetEnvironment = 'Prod' }
                'missing-variable' { $candidate.EnvironmentVariables = @($candidate.EnvironmentVariables | Select-Object -First 3) }
                'extra-variable' { $candidate.EnvironmentVariables += [pscustomobject]@{ SchemaName = 'private-unrelated-variable'; Value = 'private-value' } }
                'missing-connection' { $candidate.ConnectionReferences = @() }
                'unknown-property' { $candidate | Add-Member -NotePropertyName 'InternalData' -NotePropertyValue 'private-value' }
                'non-string-value' { $candidate.EnvironmentVariables[0].Value = @{ InternalData = 'private-value' } }
                'placeholder' { $candidate.EnvironmentVariables[0].Value = 'REPLACE_ME' }
                'missing-array' { $candidate.PSObject.Properties.Remove('ConnectionReferences') }
                'non-array' { $candidate.EnvironmentVariables = 'not-an-array' }
                'duplicate-variable' { $candidate.EnvironmentVariables += $candidate.EnvironmentVariables[0] }
                'duplicate-connection' { $candidate.ConnectionReferences += $candidate.ConnectionReferences[0] }
                'unknown-entry-property' { $candidate.EnvironmentVariables[0] | Add-Member -NotePropertyName 'InternalData' -NotePropertyValue 'private-value' }
                'empty-value' { $candidate.EnvironmentVariables[0].Value = '' }
            }
            $env:PP_DEPLOYMENT_SETTINGS_JSON = $candidate | ConvertTo-Json -Depth 10
            if ($case -eq 'absent') { $env:PP_DEPLOYMENT_SETTINGS_JSON = '' }
            if ($case -eq 'malformed') { $env:PP_DEPLOYMENT_SETTINGS_JSON = '{"private-value": INVALID' }
            if ($case -eq 'array-root') { $env:PP_DEPLOYMENT_SETTINGS_JSON = '[]' }
            if ($case -eq 'null-root') { $env:PP_DEPLOYMENT_SETTINGS_JSON = 'null' }
            'stale synthetic settings' | Set-Content $privatePath
            $message = $null
            try { & "$root\New-PrivateDeploymentSettings.ps1" @privateArgs | Out-Null } catch { $message = $_.Exception.Message }
            if ($message -ne 'Private deployment settings are missing or invalid. Check the selected environment secret, solution/target identity, JSON schema and complete package inventory.') {
                throw 'Private error was not the expected sanitized message.'
            }
            if (Test-Path -LiteralPath $privatePath) { throw 'Stale private output was not removed.' }
            if ($env:PP_DEPLOYMENT_SETTINGS_JSON) { throw 'Private JSON remained after failure.' }
        }
    }
    Assert-Passes 'private values are data, not executable PowerShell or log commands' {
        $candidate = $privateJson | ConvertFrom-Json
        $candidate.EnvironmentVariables[0].Value = '$(throw "must-not-execute")'
        $candidate.EnvironmentVariables[1].Value = "synthetic`n::warning::not-a-command%"
        $env:PP_DEPLOYMENT_SETTINGS_JSON = $candidate | ConvertTo-Json -Depth 10
        $messages = @(& "$root\New-PrivateDeploymentSettings.ps1" @privateArgs)
        $rendered = Get-Content $privatePath -Raw | ConvertFrom-Json
        if ($rendered.EnvironmentVariables[0].Value -cne '$(throw "must-not-execute")' -or
            '::add-mask::synthetic%0A::warning::not-a-command%25' -notin $messages -or
            @($messages | Where-Object { $_ -match "[`r`n]" }).Count) {
            throw 'Private values were executed, altered, or not escaped for log masking.'
        }
    }
    Assert-Passes 'Prod private values are independent from QA' {
        $candidate = $privateJson | ConvertFrom-Json
        $candidate.TargetEnvironment = 'Prod'
        $candidate.EnvironmentVariables[0].Value = 'synthetic-prod-site'
        $env:PP_DEPLOYMENT_SETTINGS_JSON = $candidate | ConvertTo-Json -Depth 10
        & "$root\New-PrivateDeploymentSettings.ps1" -Solution $poc -ExpectedSolutionName GithubSolutions_POC `
            -ExpectedTarget Prod -OutputPath $privatePath | Out-Null
        $rendered = Get-Content $privatePath -Raw | ConvertFrom-Json
        if ($rendered.EnvironmentVariables[0].Value -ne 'synthetic-prod-site') { throw 'Wrong target value rendered.' }
    }
    Assert-Passes 'BCU private configuration remains supported' {
        $env:PP_DEPLOYMENT_SETTINGS_JSON = @{
            SolutionName = 'BCURequestsWorkflow'; TargetEnvironment = 'QA'
            EnvironmentVariables = @(); ConnectionReferences = @()
        } | ConvertTo-Json
        & "$root\New-PrivateDeploymentSettings.ps1" -Solution $bcuManaged -ExpectedSolutionName BCURequestsWorkflow `
            -ExpectedTarget QA -OutputPath $privatePath | Out-Null
    }
    Assert-Passes 'workflow isolates private settings to deployment job and cleans temporary file' {
        $exportYaml = Get-Content (Join-Path $root '..\workflows\PowerPlatformDeploymentActions.yml') -Raw
        $deployYaml = Get-Content (Join-Path $root '..\workflows\DeployManagedSolution.yml') -Raw
        if ($exportYaml -match 'PP_DEPLOYMENT_SETTINGS|Test-DeploymentSettings|deployment-settings\\' -or
            $deployYaml -notmatch "secrets\[format\('PP_DEPLOYMENT_SETTINGS_\{0\}', inputs.solution-name\)\]" -or
            $deployYaml -notmatch "if: always\(\)[\s\S]*Remove-Item -LiteralPath" -or
            $deployYaml -match 'upload-artifact|secrets: inherit') {
            throw 'Private configuration scope or cleanup wiring changed.'
        }
    }

    $release = Join-Path $temp 'release'
    New-Item -ItemType Directory -Path $release | Out-Null
    Copy-Item $empty (Join-Path $release 'managed.zip')
    $digest = (Get-FileHash $empty -Algorithm SHA256).Hash
    $releaseArgs = @{
        ReleaseDirectory = $release
        ExpectedSolutionName = 'GithubSolutions_POC'
        ExpectedSha256 = $digest
        ExpectedSourceCommit = ('a' * 40)
    }
    $manifest = @{ solution = 'GithubSolutions_POC'; version = '1.0.0.16'; managedSha256 = $digest; sourceCommit = ('a' * 40) }
    $manifestPath = Join-Path $release 'manifest.json'
    $manifest | ConvertTo-Json | Set-Content $manifestPath
    Assert-Passes 'release digest and provenance match selected solution' {
        & "$root\Test-ReleaseArtifact.ps1" @releaseArgs
    }
    $releaseArgs.ExpectedSha256 = 'invalid'
    Assert-Fails 'malformed release digest' 'digest does not match' { & "$root\Test-ReleaseArtifact.ps1" @releaseArgs }
    $releaseArgs.ExpectedSha256 = ('0' * 64)
    Assert-Fails 'different release digest' 'digest does not match' { & "$root\Test-ReleaseArtifact.ps1" @releaseArgs }
    $releaseArgs.ExpectedSha256 = $digest
    foreach ($field in @('solution', 'sourceCommit', 'version', 'managedSha256')) {
        $previous = $manifest[$field]
        $manifest[$field] = 'different'
        $manifest | ConvertTo-Json | Set-Content $manifestPath
        Assert-Fails "wrong manifest $field" 'Release manifest does not match' { & "$root\Test-ReleaseArtifact.ps1" @releaseArgs }
        $manifest[$field] = $previous
    }
    $manifest | ConvertTo-Json | Set-Content $manifestPath
    Copy-Item $bcuManaged (Join-Path $release 'managed.zip') -Force
    $releaseArgs.ExpectedSha256 = (Get-FileHash $bcuManaged -Algorithm SHA256).Hash
    Assert-Fails 'wrong-solution artifact rejected even with matching digest' 'package type is incorrect' {
        & "$root\Test-ReleaseArtifact.ps1" @releaseArgs
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
