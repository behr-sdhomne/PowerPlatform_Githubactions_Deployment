$ErrorActionPreference = 'Stop'
$headers = @{
    Authorization = "Bearer $env:GH_TOKEN"
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}
$base = "$env:GITHUB_API_URL/repos/$env:GITHUB_REPOSITORY/environments/Prod"
$environment = Invoke-RestMethod -Uri $base -Headers $headers
if ($environment.can_admins_bypass -ne $false) {
    throw 'Prod must disable administrator bypass of environment protection.'
}
$rules = @($environment.protection_rules | Where-Object type -eq 'required_reviewers')
$reviewers = @($rules | ForEach-Object { $_.reviewers } | ForEach-Object { $_.reviewer.login })
if ('behr-sdhomne' -notin $reviewers) {
    throw 'Prod must require approval by behr-sdhomne in GitHub Settings > Environments.'
}
if ($environment.deployment_branch_policy.custom_branch_policies -ne $true) {
    throw 'Prod must use a selected-branches deployment policy allowing only main.'
}
$policies = Invoke-RestMethod -Uri "$base/deployment-branch-policies?per_page=100" -Headers $headers
if ($policies.total_count -ne 1 -or $policies.branch_policies[0].name -cne 'main' -or $policies.branch_policies[0].type -ne 'branch') {
    throw 'Prod deployment policy must contain exactly the main branch (not tags).'
}
Write-Output 'Production reviewer and main-only deployment policy are configured.'
