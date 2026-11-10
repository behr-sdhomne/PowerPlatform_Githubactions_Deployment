# Power Platform ALM: Dev -> QA -> Prod

Manually run **Power Platform release** on `main`. It authenticates to Dev,
exports the required **`solution-name`** input as unmanaged and managed packages, runs Solution
Checker, imports the managed package into QA, then waits for GitHub's protected
Prod environment approval. Prod imports the **same artifact ID and SHA-256**;
QA is not used as a disposable build environment. No push/release trigger exists.
Non-main dispatches skip deployment. One release runs at a time; a new release
does not cancel an in-progress deployment. GitHub concurrency retains only one
pending run, so it is not a FIFO release queue.

Use the **unique name**, not the display name: for example `GithubSolutions_POC`
or `BCURequestsWorkflow`. The same workflow supports any eligible unmanaged
solution in the configured Dev environment, provided its dependencies, deployment
permissions and per-solution target configurations are ready. It is not a
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

## Target-specific deployment settings

Every selected solution needs **both**
`deployment-settings\<unique-name>\QA.json` and
`deployment-settings\<unique-name>\Prod.json`, even if it has no connection
references or environment variables. There is no shared/default configuration
fallback. Both files are checked before authentication/export, then checked against
the managed package before QA is changed, and again before each target import.
Names and case in the input, package manifest and configuration must match exactly.

**BCU migration:** the original root-level `QA.json` and `Prod.json` templates
have moved unchanged in their mapping arrays to
`deployment-settings\BCURequestsWorkflow\`. Each now includes `SolutionName` and
`TargetEnvironment` identity fields. Run the workflow with
`solution-name: BCURequestsWorkflow` to select this configuration. If you have
filled copies of the old files elsewhere, move those values into the corresponding
solution folder and add the two identity fields rather than discarding them.
There is deliberately no legacy-path fallback.

For a new solution, generate its actual inventory from a managed export:

```powershell
pac solution create-settings --solution-zip .\GithubSolutions_POC_managed.zip --settings-file .\settings.generated.json
```

Create a folder named `GithubSolutions_POC` under `deployment-settings`, then
create `QA.json` and `Prod.json` from that inventory. Add
`"SolutionName": "GithubSolutions_POC"` and `"TargetEnvironment": "QA"` or
`"Prod"` respectively alongside the two arrays generated by PAC. Each connection
entry requires `LogicalName`, `ConnectionId`, and `ConnectorId`; each variable
entry requires `SchemaName` and `Value`. Obtain actual IDs from the target
environment. Create/authorize connections there first. Review any existing
environment variable current values in the source solution to avoid shipping
Dev-specific configuration.

For `GithubSolutions_POC`, the reported inventory is **one Excel Online (Business)
connection reference and four environment variables**. Their actual logical/schema
names, connector ID, authorized QA/Prod connection IDs, and target values still
need to be obtained. No POC configuration is fabricated here: the workflow will
refuse to release it until both real configuration files exist and pass validation.
Do not copy the empty BCU mappings as if they were valid POC settings.

The pre-import guard reads the solution's `customizations.xml` and requires an
explicit non-empty target value for every packaged environment variable and an
explicit mapping for every connection reference. It rejects unresolved
placeholders, duplicate names, and missing mappings rather than silently accepting
Dev defaults. It also rejects mappings not present in the selected solution and
configurations bound to a different solution or target. The runtime import file
contains only PAC's `EnvironmentVariables` and `ConnectionReferences` arrays;
the identity fields are validation metadata and are not passed to PAC.
Intentionally blank variables need a reviewed validator change.
Do not commit passwords, tokens or other secret configuration to these files:
use platform-supported secret stores (for example Key Vault-backed variables).
This repository is public; review connection metadata and exported solution
contents for sensitive information before uploading or committing them.

## Release runbook

1. Complete environments, reviewer protection, credentials, connection mappings,
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
Validate settings against an actual exported package using:

```powershell
.\.github\scripts\Test-DeploymentSettings.ps1 -Solution .\GithubSolutions_POC_managed.zip -Settings .\deployment-settings\GithubSolutions_POC\QA.json -ExpectedSolutionName GithubSolutions_POC -ExpectedTarget QA
.\.github\scripts\Test-DeploymentSettings.ps1 -Solution .\GithubSolutions_POC_managed.zip -Settings .\deployment-settings\GithubSolutions_POC\Prod.json -ExpectedSolutionName GithubSolutions_POC -ExpectedTarget Prod
```

Complete any pending credentials and the actual per-solution connection inventory
before a release. No fake credential secrets are supplied, and no deployment is
performed as part of this setup.

References:
[Microsoft deployment tutorial](https://learn.microsoft.com/en-us/power-platform/alm/tutorials/github-actions-deploy),
[Power Platform actions](https://github.com/microsoft/powerplatform-actions),
[CLI solution commands](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/solution).
