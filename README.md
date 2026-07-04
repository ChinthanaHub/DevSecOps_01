# DevSecOps Engineer Technical Assessment — Track 2: Multi-Cloud Platform Security & Compliance

## Executive summary

This submission is a hands-on security review against a public, intentionally-vulnerable reference repository,
standing in for the confidential ~100-workload multi-cloud estate described in the assessment's business scenario.
Scanning the reference repo with Checkov 3.3.6, tfsec, and Gitleaks produced **477 failed checks** across AWS, Azure,
and GCP Terraform. Of those, **27 curated findings** in [01-findings/findings-register.md](01-findings/findings-register.md)
directly reproduce the shape of the scenario's original audit results — public storage buckets with no access
control, a database with encryption-at-rest disabled *and* public accessibility enabled simultaneously, a
wildcard-permission IAM policy on a long-lived credential, and no centralised audit logging at all (confirmed by the
complete absence of any CloudTrail resource in the codebase, not a misconfigured one).

**Overall posture:** high-risk-by-default, with the risk concentrated in a small number of repeating patterns rather
than 27 unrelated problems. The same "no public access block" gap appears on six separate storage buckets; the same
wildcard IAM shape appears on two independent policies; the same open-management-port pattern appears on both an AWS
security group and an Azure NSG. That repetition is the most useful thing this review found — it means fixing the
*pattern* once, at the identity (Module 3), network (Module 4), and pipeline-policy (Module 2/10) layers, closes far
more risk than fixing 27 individual resources by hand, and it's why the pipeline and policy-as-code design is treated
as equally important as the findings themselves.

A non-technical read: nothing in this review found evidence of exploitation — this is a design review of what's
*possible* today, not an incident report. The one deliberately-not-fully-fixable gap (a COTS financial reconciliation
tool that cannot support storage encryption at all) is handled explicitly in Module 8 as a compensating-controls and
formal residual-risk-acceptance decision, not left as an open gap or silently worked around.

## Reference repository

**Chosen:** [bridgecrewio/terragoat](https://github.com/bridgecrewio/terragoat), cloned locally for scanning at
`reference-repos/terragoat/` (kept outside this submission's tracked history — see Approach, below).

**Why:** terragoat is the option the assessment brief itself flags as the best fit for this track — it's deliberately
vulnerable Terraform spanning AWS, Azure, and GCP in one repository, which let every module in this submission make
real same-control-different-provider comparisons (e.g. F-01/F-04/F-05 for public storage/database exposure, F-14 vs.
F-16 for open management ports on AWS vs. Azure) instead of treating each provider as a separate, hypothetical
exercise. No substitute repository was used.

## Approach, and how the modules connect

This isn't 13 independent write-ups. The review starts from real scan output (Module 1), and every design module
after it either **closes a specific finding** or **explains why a finding can't be fully closed and what stands in
its place**:

- **Module 1** (findings) is the input every other module reasons from — findings are cited by ID (`F-##`)
  throughout the rest of the repo, not re-described each time.
- **Modules 3, 4, and 5** (identity, network, data protection) are one connected design, not three: the IAM redesign
  in Module 3 scopes access by workload tag, the network design in Module 4 segments by the same sensitivity model,
  and the key management design in Module 5 encrypts by the same classification tags — a Data-tier resource in
  Module 4 is the same resource getting the encryption treatment in Module 5, and the same resource whose access
  policy was redesigned in Module 3.
- **Module 2** (pipeline) is what stops every fixed finding from regressing — it's designed against the actual
  findings from Module 1, not a generic shift-left checklist.
- **Module 6** (detection) assumes Module 1's worst finding (the wildcard CI credential) is eventually compromised,
  and walks that exact incident through detection to recovery.
- **Modules 7 and 8** (remediation) fix the three most critical findings concretely (corrected Terraform included)
  and handle the one finding that can't be fixed the same way (COTS encryption gap) with compensating controls and a
  named risk acceptance instead.
- **Module 9** (threat model) revisits the same workload from a different angle — STRIDE, rather than
  scanner-output — and finds the credential-theft pivot (IMDSv1 → wildcard role credentials) that a checklist-style
  scan alone wouldn't have surfaced.
- **Module 10** (compliance) maps five of Module 1's findings to illustrative compliance domains and shows how one
  OPA policy expresses a control identically across all three providers, rather than three parallel rule sets.
- **Module 13** (resilience) picks up the availability gaps Module 1 found as a side effect of the security review
  (no backup retention, no multi-AZ) and gives them an explicit RTO/RPO-driven design.

## Repository navigation

| Folder | Module | Status |
|---|---|---|
| [01-findings/](01-findings/) | 1 — Findings register + severity methodology | Complete |
| [02-pipeline-supply-chain/](02-pipeline-supply-chain/) | 2 — Shift-left pipeline design | Complete |
| [03-identity-governance/](03-identity-governance/) | 3 — Cross-cloud IAM design | Complete |
| [04-network-zero-trust/](04-network-zero-trust/) | 4 — Network & zero-trust design | Complete |
| [05-data-protection/](05-data-protection/) | 5 — Encryption & key management | Complete |
| [06-detection-ir/](06-detection-ir/) | 6 — Detection, monitoring & IR | Complete |
| [07-remediation/](07-remediation/) | 7, 8 — Remediation advisory + compensating controls | Complete |
| [08-threat-model/](08-threat-model/) | 9 — STRIDE threat model | Complete |
| [09-compliance/](09-compliance/) | 10 — Compliance mapping | Complete |
| [10-architecture/](10-architecture/) | 11, 12 — HLD/LLD diagrams + narrative | **Pending** — diagrams to follow separately |
| [11-resilience-dr/](11-resilience-dr/) | 13 — Resilience & DR | Complete |
| [12-presentation/](12-presentation/) | Final presentation deck | **Pending** — to follow separately |

## Tooling used

Checkov 3.3.6, tfsec (latest), Gitleaks 8.21.2 — run directly against the cloned reference repository; exact commands
and version output are cited alongside the findings they produced in
[01-findings/findings-register.md](01-findings/findings-register.md).

## Commit hygiene

This repository is built as one commit per module, in module order, with commit messages naming the module and what
it closes — not a single "final submission" commit. No secrets, credentials, or internal information are committed
at any point; the reference repository's own (intentionally vulnerable, publicly known) example credentials are
discussed by finding ID and file:line reference only, never reproduced verbatim.
