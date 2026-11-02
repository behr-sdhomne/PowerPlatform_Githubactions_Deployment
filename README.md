# Power Platform ALM: Dev -> QA -> Prod

Manually run **Power Platform release** on `main`. It authenticates to Dev,
exports `BCURequestsWorkflow` as unmanaged and managed packages, runs Solution
Checker, imports the managed package into QA, then waits for GitHub's protected
Prod environment approval. Prod imports the **same artifact ID and SHA-256**;
QA is not used as a disposable build environment. No push/release trigger exists.
Non-main dispatches skip deployment. One release runs at a time; a new release
does not cancel an in-progress deployment. GitHub concurrency retains only one
pending run, so it is not a FIFO release queue.

Solution: **BCU Requests Workflow**, unique name `BCURequestsWorkflow`, publisher
**Behr Publisher** (`behrpublisher`). Observed starting version: `1.0.0.16`.
Increment the solution version in Dev before each release. Save and publish the
intended Dev changes before dispatch; avoid editing Dev during the two exports.
The unmanaged export is a recovery/source package, not an automatic source commit
or a production backup.

## GitHub environments and variables

Initial remote setup is complete: `Dev`, `QA` and `Prod` exist, each has its
`PP_ENVIRONMENT_URL` and a main-branch-only deployment policy. Prod requires
`behr-sdhomne`, disallows administrator bypass, and permits self-review.
`PP_APP_ID`, `PP_TENANT_ID` and `PP_CLIENT_SECRET` remain deliberately unset
until the Entra registration is ready.

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

## Credentials when the Entra registration is ready

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

`deployment-settings\QA.json` and `deployment-settings\Prod.json` are deliberate
empty templates, not invented connection IDs. They work only for solutions with
no connection references or environment variables. Before the first release,
generate an inventory from a managed export using the Power Platform CLI:

```powershell
pac solution create-settings --solution-zip .\BCURequestsWorkflow_managed.zip --settings-file .\settings.generated.json
```

Use the inventory to populate each target's checked-in JSON. Each connection
entry requires `LogicalName`, `ConnectionId`, and `ConnectorId`; each variable
entry requires `SchemaName` and `Value`. Obtain actual IDs from the target
environment. Create/authorize connections there first. Review any existing
environment variable current values in the source solution to avoid shipping
Dev-specific configuration.

The pre-import guard reads the solution's `customizations.xml` and requires an
explicit non-empty target value for every packaged environment variable and an
explicit mapping for every connection reference. It rejects unresolved
placeholders, duplicate names, and missing mappings rather than silently accepting
Dev defaults. Intentionally blank variables need a reviewed validator change.
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
   **Run workflow**, branch `main`.
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

The `managed-release-*` artifact contains the managed ZIP and provenance manifest.
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
.\.github\scripts\Test-DeploymentSettings.ps1 -Solution .\BCURequestsWorkflow_managed.zip -Settings .\deployment-settings\QA.json
.\.github\scripts\Test-DeploymentSettings.ps1 -Solution .\BCURequestsWorkflow_managed.zip -Settings .\deployment-settings\Prod.json
```

Registration and connection inventory are still pending. No fake credential
secrets are supplied, and no deployment is performed as part of this setup.

References:
[Microsoft deployment tutorial](https://learn.microsoft.com/en-us/power-platform/alm/tutorials/github-actions-deploy),
[Power Platform actions](https://github.com/microsoft/powerplatform-actions),
[CLI solution commands](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/solution).
