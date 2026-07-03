# Severity & Prioritisation Methodology

## Why not just use scanner-native severity

Checkov's OSS output ships each check without a severity field unless it's wired into a paid Bridgecrew/Prisma Cloud
backend (confirmed against this repo — all 477 failed checks came back with `severity: null`). tfsec assigns severity,
but its scale doesn't account for two things that matter more here than in a single-account estate: **how exposed the
workload already is**, and **how much remediation bandwidth actually exists**. With ~100 workloads and a hard go-live
deadline, a rating scheme that just echoes CVSS-style technical severity would send the review down the wrong list —
technically "critical" findings on an isolated dev sandbox would out-rank a "high" finding on an internet-facing
production database. So severity here is a function of exposure and blast radius, not just the control that's missing.

## Rating factors

Each finding is scored on four axes, then rolled into a single severity band:

| Factor | What it captures |
|---|---|
| **Exposure** | Is the resource reachable from the public internet today, or only from inside the VPC/VNet/VPC-equivalent? |
| **Data sensitivity** | Does the resource hold customer data, financial data, credentials, or is it non-sensitive (static assets, logs)? |
| **Exploitability** | Does exploiting this require no further steps (e.g. an open S3 bucket), or does it require chaining with another weakness? |
| **Blast radius** | If exploited, does it affect one workload, one account, or does it cascade (e.g. a wildcard IAM credential valid across an account)? |

## Severity bands

| Band | Definition | Response expectation |
|---|---|---|
| **Critical** | Public exposure + sensitive data or credential exposure, exploitable with no further steps, and/or blast radius beyond a single workload (e.g. an account-wide wildcard IAM credential). | Fix before go-live. No exception without named executive sign-off. |
| **High** | Either public exposure of non-trivial data, or a control gap that materially weakens containment (e.g. no encryption at rest on a database that isn't yet public, unrestricted egress). | Fix before go-live, or accepted as time-bound residual risk with a compensating control and a named owner. |
| **Medium** | Internal-only exposure, or a hardening gap that increases dwell time/detection difficulty rather than enabling direct compromise (e.g. missing access logging, missing versioning). | Scheduled within the remediation programme; not a go-live blocker unless it's the only detective control for a Critical/High finding. |
| **Low** | Best-practice / hygiene gaps with no direct exploit path (e.g. missing resource tags, missing descriptions on security group rules). | Backlog; fixed opportunistically or via the pipeline gate once Module 2 is live so it never regresses. |

## Prioritisation logic across ~100 workloads

Findings are prioritised, not just severity-sorted, using three additional lenses — because with limited remediation
bandwidth the question is never "what's broken" alone, it's "what gets fixed first, and what gets formally accepted
as risk":

1. **Landing zone tier.** The newer, continuous-compliance landing zone already has guardrails and detection; a
   Critical finding there is partially compensated by monitoring. The same finding in the earlier account-per-environment
   tier has no compensating control at all, so it's treated as higher priority even at equal technical severity.
2. **Recurrence.** A misconfiguration that shows up once is a workload problem. The same misconfiguration recurring
   across many of the ~100 workloads (e.g. every S3 bucket missing a public access block) is a **pattern**, and gets
   fixed once at the pipeline/policy layer (Module 2/10) rather than 100 times by hand — this is worth more than
   fixing any single instance.
3. **Fix cost vs. risk-acceptance cost.** Some findings (e.g. `storage_encrypted = false` on an RDS instance) are a
   one-line Terraform change with a maintenance-window restart. Others (e.g. the COTS encryption limitation in
   Module 8) cannot be fixed in the available time at any cost — those get compensating controls and a formal,
   time-bound residual risk acceptance instead of sitting on a "to fix" list indefinitely.

This is the same logic applied to [findings-register.md](findings-register.md): the **Priority Wave** column reflects
this combined view, not severity alone.
