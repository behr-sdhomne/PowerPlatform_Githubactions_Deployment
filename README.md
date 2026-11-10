# Power Platform ALM: Dev -> QA -> Prod

Manually run **Power Platform release** on `main`. It authenticates to Dev,
exports the required **`solution-name`** input as unmanaged and managed packages, runs Solution
Checker, imports the managed package into QA, then waits for GitHub's protected
Prod environment approval. Prod imports the **same artifact ID and SHA-256**;
QA is not used as a disposable build environment. No push/release trigger exists.
Non-main dispatches skip deployment. One release runs at a time; a new release
does not cancel an in-progress deployment. GitHub concurrency retains only one
pending run, so it is not a FIFO release queue.

This is a **GitHub Actions** deployment route, not a native Power Platform
Pipeline. It does not require enabling **Managed Environments**. A managed
solution ZIP is a deployment package type, not a Managed Environment setting.
Normal Dataverse access, component licensing and connection authorization still
apply. The workflow is reusable, but each solution's connection references and
environment-variable values remain inherently target-specific; setup is one
private JSON secret per solution in each target environment.

Use the **unique name**, not the display name: for example `GithubSolutions_POC`
or `BCURequestsWorkflow`. The same workflow supports any eligible unmanaged
solution in the configured Dev environment, provided its dependencies, deployment
permissions and private per-solution target configurations are ready. It is not a
cross-tenant or arbitrary-environment deployment tool. Managed-only, system or
non-exportable solutions are not made eligible by entering their name; Dataverse
export/authentication errors fail the run.

Names must start with an ASCII letter and contain only ASCII letters, digits and
underscores (1-65 characters); reserved Windows device names are rejected.
Validation occurs before a name is used in a filesystem path or export action.
User input is passed through environment variables, never interpolated into
PowerShell source. All solutions share the release concurrency lock because
imports into the same QA/Prod environments must not overlap.

Increment the selected solution's version in Dev before each release. Save and publish the
intended Dev changes before dispatch; avoid editing Dev during the two exports.
The unmanaged export is a recovery/source package, not an automatic source commit
or a production backup.

## GitHub environments and variables

Initial remote setup is complete: `Dev`, `QA` and `Prod` exist, each has its
`PP_ENVIRONMENT_URL` and a main-branch-only deployment policy. Prod requires
`behr-sdhomne`, disallows administrator bypass, and permits self-review.
The generic workflow uses the same existing environment credentials and URLs;
changing the selected solution does not change or recreate them. Complete
`PP_APP_ID`, `PP_TENANT_ID` and `PP_CLIENT_SECRET` if not already configured.

Use exactly `Dev`, `QA`, and `Prod` in **Settings > Environments**. Set these
**environment variables**:

| Variable | Dev | QA | Prod |
| --- | --- | --- | --- |
| `PP_ENVIRONMENT_URL` | `https://orgfd9b912f.crm.dynamics.com` | `https://org94225411.crm.dynamics.com` | `https://org4bd02029.crm.dynamics.com` |
| `PP_APP_ID` | Pending Entra application/client ID | Pending QA application/client ID | Pending Prod application/client ID |
| `PP_TENANT_ID` | Pending directory/tenant ID | Pending directory/tenant ID | Pending directory/tenant ID |

Pending values above are documentation placeholders, **not real configured
credentials**. Leave them absent until registration is complete. Environment IDs
and organization IDs are not tenant IDs or client IDs.

| Environment | Environment ID | Organization ID |
| --- | --- | --- |
| Dev | `7c561f00-172d-4270-a433-6aa0b88b5eb7` | `c9e4d58f-5664-4e50-83cc-47f3525243ae` |
| QA | `4e16e120-80bb-442e-ada9-54b657c8806f` | `601770f6-2f82-4c82-bc07-be2328be6660` |
| Prod | `97b4ff6d-d065-4041-989f-06e4f5b7c6a9` | `47998134-cbcd-4aa9-9214-89956c0899ef` |

For **Prod**, enable **Required reviewers** and select `behr-sdhomne`. Select
**Selected branches and tags**, and add exactly one **branch** rule: `main`.
Disable administrator bypass where available. Preserve existing stronger
protections; reconcile additional branch rules deliberately rather than deleting
them blindly. The workflow fails closed if the reviewer or exact branch rule is
missing, administrator bypass is enabled, or GitHub's environment API cannot
be read.

Because `behr-sdhomne` is currently the sole reviewer and may initiate the run,
leave **Prevent self-review** unchecked if that person must also release.
This is a manual gate, **not separation of duties**. For independent approval,
add another authorized reviewer and then enable prevention of self-review.
GitHub environment protection is the actual gate; YAML alone cannot create it.
Apply main-only deployment restrictions to Dev and QA as well.

Allow GitHub Actions and the referenced Microsoft/GitHub actions in repository
policy. The workflow token requests only `contents: read` and `actions: read`.
All third-party actions are pinned to verified full commit SHAs. Review and
update these pins periodically, including the Microsoft Checker behavior.
Each export/deployment job installs PAC using the pinned official
`microsoft/powerplatform-actions/actions-install` before authentication and other
Power Platform actions. Jobs use independent GitHub-hosted runners: installing
PAC on your workstation does not install it there, and an export-job install
does not carry over to QA or Prod. If an earlier run failed with
`PAC is not installed`, start a **new manual run on updated main**; rerunning the
old run uses its original workflow revision. No retry is initiated automatically.

## Credentials and application user access

Use the supported service-principal client-secret authentication inputs for the
Microsoft Power Platform actions. Prefer separate app registrations/secrets per
environment to limit blast radius. A shared registration also works if explicitly
authorized in each environment.

Create a Dataverse **application user** for the relevant registration in each
environment and assign the roles needed to export/check in Dev and import/publish
in QA/Prod. Microsoft's tutorial uses System Administrator; have your platform
administrator assess an appropriately scoped deployment role rather than assuming
a generic least-privilege role covers all solution components. Ensure the
application user can use the required connections and the Checker service.

In **Settings > Environments > (environment) > Environment secrets**, add the
secret **`PP_CLIENT_SECRET`** with the client secret **value**, not its secret ID.
Never paste it into chat, YAML, JSON, command arguments, or a commit.
Alternatively, run each command interactively; `gh` prompts for the value:

```powershell
gh secret set PP_CLIENT_SECRET --env Dev --repo behr-sdhomne/PowerPlatform_Githubactions_Deployment
gh secret set PP_CLIENT_SECRET --env QA --repo behr-sdhomne/PowerPlatform_Githubactions_Deployment
gh secret set PP_CLIENT_SECRET --env Prod --repo behr-sdhomne/PowerPlatform_Githubactions_Deployment
```

Set `PP_APP_ID` and `PP_TENANT_ID` as environment variables after registration.
Missing, empty, zero-GUID, and recognizable placeholder configuration fails before
authentication. Rotate secrets before expiry. This workflow does not claim OIDC
federation support and does not request `id-token: write`.

## Private target-specific deployment settings

QA and Prod are direct jobs in `PowerPlatformDeploymentActions.yml`, each bound
to its own GitHub environment. They share deployment steps through
`.github\actions\deploy-managed-solution\action.yml`, a local composite action.
The old reusable `DeployManagedSolution.yml` workflow has been removed. This
avoids reusable-workflow secret forwarding entirely: no `secrets: inherit`,
credential copies into Dev, or broader repository secrets are required.
The calling job supplies only its authentication secret and the selected
solution's private settings to the deployment steps.

GitHub documents that reusable-workflow callers must explicitly pass secrets,
even when the called job declares an environment; otherwise they can resolve
empty. The prior caller omitted that forwarding, causing the QA credential guard
to fail despite an environment secret existing. See
[GitHub reusable workflow secret semantics](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows#using-inputs-and-secrets-in-a-reusable-workflow).
After publishing this correction, start a new manual run on updated `main`,
not a rerun of an older workflow revision. Local validation does not execute
GitHub's environment-secret resolution; the next authorized run must confirm it.

All target connection IDs, connector IDs, schema/logical names and values belong
in **GitHub environment secrets**, not files tracked in this public repository.
Use one JSON secret per solution, with the **same secret name** in QA and Prod
and different target-specific contents. No GitHub variable is required for these
private values; ordinary variables are not masked like secrets.

| Environment | Secret name | Contents |
| --- | --- | --- |
| QA | `PP_DEPLOYMENT_SETTINGS_GITHUBSOLUTIONS_POC` | POC JSON with `TargetEnvironment: QA` |
| Prod | `PP_DEPLOYMENT_SETTINGS_GITHUBSOLUTIONS_POC` | POC JSON with `TargetEnvironment: Prod` |
| QA | `PP_DEPLOYMENT_SETTINGS_BCUREQUESTSWORKFLOW` | BCU JSON with `TargetEnvironment: QA` |
| Prod | `PP_DEPLOYMENT_SETTINGS_BCUREQUESTSWORKFLOW` | BCU JSON with `TargetEnvironment: Prod` |

For any other solution, use `PP_DEPLOYMENT_SETTINGS_<UNIQUE_NAME_IN_UPPERCASE>`.
GitHub secret names are case-insensitive; JSON `SolutionName`, package identity
and dispatch input must still match **exactly**, including case. Do not configure
solutions distinguished only by casing as separate secret entries. Each secret
holds only one solution, avoiding a shared multi-solution registry. Secret names
are at most 88 characters with the accepted solution-name limit. The complete
JSON must fit GitHub's 48 KB per-secret limit; do not silently truncate or split
it. Very large configurations require a separately reviewed secure-storage design.

In **Settings > Environments > QA (then Prod) > Environment secrets**, add the
appropriate name and paste the target-specific JSON. Store these only at
environment scope, not repository/organization scope or in Dev. GitHub resolves
secrets by name and can fall back to broader scopes if configured there; the
workflow cannot distinguish that origin, so administrators must enforce this
scope rule. Never paste actual values into chat or public files. The existing
`PP_CLIENT_SECRET` authentication secret is separate and unchanged.

The JSON must be a single object with exactly these four properties. This
**illustrative placeholder-only example** describes the POC shape, not its real
schema names, connector or connections. All angle-bracket placeholders must be
replaced privately; placeholders fail validation.

```json
{
  "SolutionName": "GithubSolutions_POC",
  "TargetEnvironment": "QA",
  "EnvironmentVariables": [
    { "SchemaName": "<ACTUAL_SITE_SCHEMA_NAME>", "Value": "<QA_SHAREPOINT_SITE_URL>" },
    { "SchemaName": "<ACTUAL_LIST_1_SCHEMA_NAME>", "Value": "<QA_LIST_1_VALUE>" },
    { "SchemaName": "<ACTUAL_LIST_2_SCHEMA_NAME>", "Value": "<QA_LIST_2_VALUE>" },
    { "SchemaName": "<ACTUAL_LIST_3_SCHEMA_NAME>", "Value": "<QA_LIST_3_VALUE>" }
  ],
  "ConnectionReferences": [
    {
      "LogicalName": "<ACTUAL_CONNECTION_REFERENCE_LOGICAL_NAME>",
      "ConnectionId": "<QA_AUTHORIZED_CONNECTION_ID>",
      "ConnectorId": "<ACTUAL_CONNECTOR_ID>"
    }
  ]
}
```

For Prod use `"TargetEnvironment": "Prod"` and the actual production site/list
values and connection ID. Every entry field is a non-empty JSON **string**;
list titles versus GUIDs depend on what the solution expects, not the pipeline.
Both arrays are required, even when empty. Use the actual inventory, not the
example's count, for other solutions.

The user confirmed the four POC variables represent **one SharePoint site and
three SharePoint lists**. An earlier inventory identified an **Excel Online
(Business)** reference. Do not infer the reference's connector from the variable
values: obtain its actual logical name and connector ID, and verify whether an
additional SharePoint reference exists in the exported solution. Create and
authorize the actual required connections in QA and Prod. Four SharePoint-related
variables alone do not prove which connector the solution uses.

To obtain the real inventory, generate settings from a managed export on an
approved local machine, outside this public checkout:

```powershell
pac solution create-settings --solution-zip .\GithubSolutions_POC_managed.zip --settings-file .\QA.private.json
```

Add the two identity properties, complete the PAC arrays privately, and prepare
the Prod copy with its own values. Files named `*.private.json` and the old
`deployment-settings` directory are git-ignored as an extra guard, not a security
boundary. Prefer keeping private files outside the checkout; never `git add -f`
them. If real configuration was previously committed, deleting the latest file
does not remove it from history: assess exposure and rotate any credentials.

**BCU migration:** public `deployment-settings\BCURequestsWorkflow\QA.json` and
`Prod.json` templates have been removed. Put equivalent JSON (including
`SolutionName: BCURequestsWorkflow` and the correct target) into the BCU
environment secrets listed above. Their previously empty arrays are valid only
if the actual BCU package has no references or variables. There is no tracked-file,
legacy-path, variable or blank-settings fallback.

Dev never reads QA or Prod private configuration. Each deployment job receives
only the selected solution's secret from its **own** environment; Prod's secret
is available only after environment approval. Consequently, private settings can
no longer be fully preflighted in Dev. QA validates its configuration before its
import; Prod validates its configuration after approval but before its import.
A missing/invalid Prod secret may stop a release after QA has succeeded.

The guard verifies package identity, target identity, array shapes, duplicates,
placeholders, extra mappings and completeness against `customizations.xml` and
separate `environmentvariabledefinitions/<schema>/environmentvariabledefinition.xml`
entries. It reads schema metadata only, not packaged current values, for this inventory.
Wrong-solution or wrong-target configuration is rejected. Blank values require a
reviewed validator change. No JSON content is interpolated into shell source.
The loader registers masks for the complete JSON and individual strings and
reports only sanitized errors; do not enable runner/step debug logging or print
the configuration yourself. It materializes only PAC's two arrays in
`RUNNER_TEMP\pp-deployment-settings.json`, never a release artifact or job output.
The private input is cleared from the loader process environment and an
`always()` cleanup removes the temporary file on success or failure.
Hosted runners are ephemeral; hard termination can skip cleanup, so this workflow
uses hosted runners rather than promising secure file deletion on shared hosts.

This protects **target configuration**, not sensitive Dev values already embedded
in exported ZIPs or Checker reports. Remove inappropriate source current values
and review exports before release. GitHub log masking is defense in depth, not
a substitute for trusting/reviewing actions, platform logs and authorized users.

## Release runbook

1. Complete environments, reviewer protection, credentials, both private target secrets,
   dependency installation, licensing and target access. Run local validation
   below before merging the workflow into `main`.
2. Save/publish and increment the Dev solution version. Confirm no release is
   already waiting for approval. In **Actions > Power Platform release**, choose
   **Run workflow**, branch `main`, and enter the required solution unique name
   (for example `GithubSolutions_POC`).
3. Review Solution Checker results and QA import. The pinned official
   `check-solution` implementation uses `HighIssueCount` with threshold `0`, and
   analysis errors fail the run. Review lower-severity findings too; a clean
   Checker result is not an integration or business acceptance test.
4. Perform QA acceptance tests: request creation, permissions, integrations,
   connection authorization, cloud flow activation and representative failure
   paths. Record evidence with the run/change record before approval.
5. In the waiting Prod deployment, `behr-sdhomne` reviews the QA evidence, digest,
   planned production change and backup readiness, then approves or rejects.
   Confirm production behavior after the import; an import success is not a
   smoke-test pass.

The `managed-release-<solution>-<run>-<attempt>` artifact contains `managed.zip`
and a provenance manifest recording the selected solution, version, commit and
digest. Generic ZIP filenames are isolated inside jobs and immutable artifacts;
the unique artifact ID is promoted to both targets, not a filename/name search.
Each target also checks the actual package solution identity and manifest, so an
artifact for another solution is rejected even if its hash is supplied.
The `dev-unmanaged-*` artifact preserves the unmanaged ZIP even if Checker fails
after export. Artifacts expire after 30 days: download to an approved retained
release store if longer retention or disaster recovery requires it. Artifact
permissions/retention do not replace a sensitive-data review.

The import uses managed **update**, not stage-and-upgrade, and does not force
overwrite unmanaged customizations. It does not remove obsolete components.
Plan deletions and managed upgrades separately with dependency review and
backups. No automatic destructive rollback is attempted: a lower-version managed
ZIP is not a guaranteed rollback. Arrange supported environment backups/restores
with the platform administrator before approval, understand data-loss implications,
and prefer a tested forward fix when appropriate.

Do not rerun only failed jobs after changing QA evidence, credentials, or settings:
start a new full run so the artifact, source commit and acceptance evidence align.
A manual cancellation/timeout can leave a Dataverse async import running; inspect
solution history and completion status before starting another release.

## Local validation

Run `actionlint` from the repository root and run
`pwsh -NoProfile -File .\.github\scripts\Test-Pipeline.ps1` for the guard tests.
All guard tests use synthetic values and temporary packages, not real secrets.
For an authorized local validation of a private file outside the checkout, use:

```powershell
$env:PP_DEPLOYMENT_SETTINGS_JSON = Get-Content 'C:\ApprovedPrivateLocation\QA.private.json' -Raw
$path = Join-Path $env:TEMP 'pp-settings.private.json'
try {
    .\.github\scripts\New-PrivateDeploymentSettings.ps1 -Solution 'C:\ApprovedPrivateLocation\GithubSolutions_POC_managed.zip' -ExpectedSolutionName GithubSolutions_POC -ExpectedTarget QA -OutputPath $path | Out-Null
} finally {
    $env:PP_DEPLOYMENT_SETTINGS_JSON = $null
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
}
```

Do not run local validation in a recorded/shared shell with real configuration.
The loader's mask commands are consumed by GitHub Actions; they are not a local
terminal redaction mechanism.

Complete any pending credentials and the actual per-solution connection inventory
before a release. No fake credential secrets are supplied, and no deployment is
performed as part of this setup.

References:
[Microsoft deployment tutorial](https://learn.microsoft.com/en-us/power-platform/alm/tutorials/github-actions-deploy),
[Power Platform actions](https://github.com/microsoft/powerplatform-actions),
[CLI solution commands](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/solution).
