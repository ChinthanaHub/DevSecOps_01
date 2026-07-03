# Identity & Access Governance Across Clouds — Module 3

## Framing

AWS IAM, Entra ID/Azure RBAC, and GCP IAM are not the same model wearing different names — AWS is resource-policy +
identity-policy dual-evaluation, Azure is role-assignment-on-scope, GCP is role-binding-on-resource-hierarchy. Treating
them as interchangeable produces three parallel, divergent IAM strategies that drift the moment nobody's looking. The
design below is deliberately **one governance model with three provider-specific implementations**, not three models.

## 1. Workload identity federation across clouds

**Decision: OIDC-based federation everywhere a pipeline or workload needs cloud credentials. No long-lived
cross-cloud credentials, anywhere, full stop.**

| Approach | AWS | Azure | GCP |
|---|---|---|---|
| Mechanism | IAM Role + OIDC identity provider trusting GitLab's OIDC issuer | Workload Identity Federation (federated credential on an App Registration / Managed Identity) | Workload Identity Federation pool + provider trusting GitLab OIDC |
| What the pipeline holds | Nothing persistent — a short-lived STS token requested per job, scoped to the `sub` claim (project + branch/environment) | Nothing persistent — an Entra token exchanged per job | Nothing persistent — a short-lived access token exchanged per job |

**Why federation over long-lived cross-cloud credentials:** F-11 and F-18 in the findings register are both the same
underlying failure mode — a long-lived, static credential (an IAM user access key) that outlives any single pipeline
run and is committed or leaked as a result. A federated credential can't be committed to a repo because it never
exists at rest; it's minted per job and expires at the end of it. This closes off the entire class of finding, not
just the specific instance found. It also means onboarding Azure/GCP doesn't require inventing a new secrets-
distribution mechanism — the same OIDC trust pattern is configured three times, once per provider, using each
provider's federation primitive, rather than building a fourth, GitLab-specific credential store.

## 2. Least-privilege model for human access

- **Standing access = read-only, everywhere.** No human identity holds standing write/admin access to a production
  landing zone account/subscription/project. Read access for review, monitoring, and audit is standing because it
  carries no mutation risk.
- **Elevation is just-in-time**, requested through the identity provider (see below) against a specific role for a
  specific account/subscription/project, time-bound (default 4 hours, hard cap 8), and requires a stated reason
  logged alongside the grant.
- **Break-glass / emergency access:** a small number of pre-provisioned, disabled-by-default emergency credentials
  per provider (AWS: a dedicated `break-glass` IAM role with a hardware-token-gated activation; Azure: an emergency
  access "cloud-only" account excluded from Conditional Access, per Microsoft's documented pattern; GCP: an
  organization-restricted emergency access group). Activation of any of these:
  - Immediately pages the ITSO-equivalent stakeholder and the identity governance owner (not just logs it).
  - Auto-expires (session + credential rotation) within a fixed window, not left standing "until someone remembers."
  - Generates a mandatory post-use review — break-glass access that's used without a follow-up review is itself
    escalated as a governance finding.

## 3. Privileged (admin-level) access — time-bound, not standing

Admin-level roles (`AdministratorAccess`-equivalent, Owner, `roles/owner`) are **never** assigned as a standing
role binding on any account/subscription/project in either landing zone tier. Instead:

1. Eligible identities are pre-registered against an eligible-role mapping (who *can* request Owner on which scope).
2. A request triggers an approval workflow with a named, different approver (no self-approval), auto-expiring after
   the stated task window.
3. Every activation is logged to the centralised audit trail (Module 6) with the requester, approver, scope, and
   duration — this is the audit evidence a compliance mapping (Module 10) would point to for privileged-access
   controls.
4. The **newer, continuous-compliance landing zone tier** enforces this technically (policy denies standing
   Owner/Admin role assignment outright). The **older, account-per-environment tier** cannot yet enforce this
   automatically — it's a process control there until it's brought under the same guardrails, and that gap is itself
   tracked as an accepted, time-bound risk (same pattern as Module 8's compensating-controls reasoning, applied to
   governance debt rather than a technical control).

## 4. Redesigning the wildcard CI service account finding (F-11 / F-12)

The scenario's audit found a CI service account with a wildcard IAM policy. In this repository that's two concrete
resources: `aws_iam_user_policy.userpolicy` (`ec2:*`, `s3:*`, `lambda:*`, `cloudwatch:*` on `Resource:"*"`, attached to
a **user** with a static access key) and `aws_iam_role_policy.ec2policy` (`s3:*`, `ec2:*`, `rds:*` on `Resource:"*"`,
attached to the EC2 instance role). Redesign, not just "make it more restrictive":

**Step 1 — remove the standing credential entirely.** `aws_iam_user.user` and its `aws_iam_access_key` are deleted.
A CI job never authenticates as an IAM user again; it authenticates via the OIDC role above, scoped to the specific
GitLab project/protected-branch `sub` claim, so no other project's pipeline can assume it.

**Step 2 — replace the wildcard policy with a scoped, resource-constrained policy** built from what the pipeline
in Module 2 actually needs to do (plan/apply against a specific state backend, read specific parameter store paths,
and nothing else):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformStateAccess",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::tf-state-${workload_id}",
        "arn:aws:s3:::tf-state-${workload_id}/*"
      ]
    },
    {
      "Sid": "StateLock",
      "Effect": "Allow",
      "Action": ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"],
      "Resource": "arn:aws:dynamodb:*:*:table/tf-lock-${workload_id}"
    },
    {
      "Sid": "ManageOnlyThisWorkloadsResources",
      "Effect": "Allow",
      "Action": ["ec2:Describe*", "rds:Describe*", "rds:ModifyDBInstance", "s3:GetBucket*", "s3:PutBucket*"],
      "Resource": "*",
      "Condition": {
        "StringEquals": { "aws:ResourceTag/workload-id": "${workload_id}" }
      }
    }
  ]
}
```

The third statement is the load-bearing change: instead of `Resource:"*"` with no condition, every mutating action
is tag-scoped to the workload the pipeline is actually responsible for. A compromised token for workload A's pipeline
cannot touch workload B's database, which directly closes the blast-radius problem the original wildcard created —
this is also the finding used as the worked incident scenario in
[06-detection-ir/monitoring-ir-plan.md](../06-detection-ir/monitoring-ir-plan.md).

**Step 3 — apply the equivalent constraint in Azure and GCP** so the same CI identity model holds once those
providers onboard: an Azure custom role scoped to a resource group + tag condition (rather than `Contributor` at
subscription scope), and a GCP custom role bound at the project level with a `resource.tag` condition — same
shape, provider-native syntax.

## How this reads as one story, not three IAM strategies

Federation removes standing credentials → least-privilege removes standing human access → time-bound elevation
removes standing privileged access → the CI redesign removes the one place a wildcard, standing credential actually
existed in this repo. Every layer answers the same question — "what could an attacker do with a credential that
exists right now" — and the answer, after this design, is "nothing beyond one tagged workload, for a few hours at
most," on every provider, not just AWS.
