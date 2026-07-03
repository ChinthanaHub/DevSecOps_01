# Shift-Left Pipeline & Software Supply Chain Design — Module 2

## Design goal

Every finding in [01-findings/findings-register.md](../01-findings/findings-register.md) should have been caught
**before merge**, not discovered by an internal audit sampling 12 of ~100 workloads after the fact. This pipeline is
designed against that specific bar: every gate below maps to a finding category we actually found, not a generic
best-practice checklist.

The estate already runs a self-managed GitLab instance with group- and project-level runners, so this is a
`.gitlab-ci.yml`-native design, not a bolt-on tool that assumes a different platform.

## Gates, named tools, and what each one checks

| Stage | Tool | What it checks | Why this tool |
|---|---|---|---|
| 1. Secrets | **Gitleaks** | Full-history + diff scan for committed credentials — this is what would have caught F-18 (hardcoded AWS access keys) and F-20 (Azure high-entropy secret) before merge | Fast, no daemon required, works identically across every provider's Terraform since it scans text, not cloud APIs |
| 2. IaC misconfiguration | **Checkov** (primary), **tfsec** (secondary, drift-check) | Provider-aware static analysis against Terraform — catches F-01–F-06 (public exposure), F-11/F-12 (wildcard IAM), F-14/F-16 (open security groups/NSGs) | Checkov is the only OSS scanner with equal-depth AWS **and** Azure **and** GCP rule packs, which matters directly once Azure/GCP onboard — one tool, one ruleset, not three |
| 3. Software supply chain / SCA | **Trivy** | Dependency + container image CVE scanning, and SBOM generation (CycloneDX) for anything the pipeline builds (Lambda packages, container images for the COTS wrapper, etc.) | Single binary, covers both the IaC-adjacent supply chain (provider plugin versions, module sources) and any application dependencies bundled alongside the Terraform |
| 4. Policy-as-code | **OPA / Conftest** | Org-specific rules that go beyond generic scanner defaults — e.g. "no resource may be tagged `data-classification:restricted` without encryption enabled" (ties Module 5's classification model directly into the gate) | This is the layer that lets one rule express a control identically across AWS/Azure/GCP resource types (see [09-compliance/compliance-mapping.md](../09-compliance/compliance-mapping.md)) rather than hand-maintaining Checkov custom policies per provider |
| 5. Terraform plan review | `terraform validate` + `terraform plan` (policy-checked output) | Confirms the above gates are evaluated against what will actually be applied, not just what's on disk | Standard, but sequenced last intentionally — no point planning something that already failed a scan |
| 6. Protected-environment approval | GitLab protected environment + required approvers | Human security sign-off before `apply` reaches a production-tier landing zone | Matches the scenario's requirement for formal go-live security sign-off — this is where accountability is recorded, not just automated |

## Hard-fail vs. soft-fail, and why

Not every finding should block a merge — a pipeline that hard-fails on everything gets bypassed or disabled under
deadline pressure, which is worse than a slightly noisier one that stays on.

| Fails the pipeline (blocking) | Warns only (soft-fail, logged to findings backlog) |
|---|---|
| Gitleaks: any confirmed secret match | Checkov/tfsec: Low severity per [severity-methodology.md](../01-findings/severity-methodology.md) (e.g. missing tags, missing SG rule descriptions) |
| Checkov/tfsec: any finding rated **Critical** (public data exposure, wildcard IAM `Resource:"*"`, encryption-at-rest disabled on a database) | Checkov/tfsec: **Medium** findings on a workload not yet tagged `data-classification:restricted` |
| OPA/Conftest: violation of a hard organisational rule (e.g. no public storage, no wildcard IAM actions) | Trivy: CVEs below a defined CVSS threshold with no known exploit |
| Trivy: CVSS-Critical with a known exploit and an available fix | New/unpatched CVEs with no fix yet published (tracked, not blocked — blocking on an unfixable CVE just stalls delivery) |

The split is deliberate: **hard-fail gates map to findings that would put the programme in the same position as the
original audit** (public exposure, wildcard credentials, missing encryption). Everything else is real signal that
feeds the findings register and gets triaged on the cadence in the severity methodology, rather than becoming a merge
blocker that gets routinely overridden.

## Scaling across ~100 workloads without becoming a bottleneck

A single fixed gate depth for all 100 workloads either over-scans low-risk static sites or under-scans the COTS
financial reconciliation tool. Instead, gate depth is **tiered by workload criticality**, tagged at the repo/module
level:

- **Tier A** (holds regulated/financial/customer data, or sits in the newer continuous-compliance landing zone as a
  production dependency): full gate set, zero soft-fail exceptions on Critical/High, mandatory protected-environment
  approval.
- **Tier B** (internal tooling, non-production, lower-sensitivity data): full scan set still runs, but only Critical
  findings hard-fail; High is a fast-follow warn.
- **Tier C** (legacy/COTS-wrapped workloads that can't be re-platformed before go-live, e.g. the financial
  reconciliation tool): scans still run for visibility, but findings that map to a known, accepted compensating
  control (Module 8) are suppressed from hard-fail via a documented Checkov/OPA exception list — not silently
  ignored, explicitly waived with an expiry date.

This means the pipeline doesn't get slower as workloads are onboarded — it runs the same automated gate set
everywhere, and only the **enforcement strictness** changes by tier, which is a config value, not a new pipeline.

## SBOM, dependency provenance, and feedback into the backlog

- Trivy generates a CycloneDX SBOM on every build artefact (Lambda zips, container images) as a pipeline artefact,
  retained per the project's artefact retention policy.
- Any CVE Trivy finds is written to the same findings register schema as Module 1 (`01-findings/findings-register.md`)
  via a scheduled job that appends new SCA findings with a `source: pipeline` tag, so supply-chain risk isn't tracked
  in a separate spreadsheet from IaC risk — one register, one prioritisation model.
- Provenance: build jobs run in ephemeral, group-managed runners only (no project-level runner may build a release
  artefact) so the SBOM's claims about what went into a build are trustworthy.

## What changes once Azure/GCP workloads onboard

Almost nothing changes in the pipeline shape — this is the point of picking Checkov and OPA/Conftest as the
core tools: both already understand Azure and GCP resource types natively (confirmed in this review — the same
Checkov run that found the AWS issues also flagged Azure Storage/NSG/SQL issues and GCP Cloud SQL/BigQuery issues in
one pass, see [01-findings/findings-register.md](../01-findings/findings-register.md)). The changes that **do** happen:

1. New cloud-specific credentials for the pipeline itself, issued via workload identity federation, not long-lived
   keys (see [03-identity-governance/cross-cloud-iam-design.md](../03-identity-governance/cross-cloud-iam-design.md)).
2. New OPA policy bundle entries only where a control genuinely has no cross-provider equivalent (rare — most,
   like "no public storage" or "no wildcard IAM," translate directly).
3. Tier classification gets re-run against the new workloads before their first pipeline execution, not after.

## Deliverable

See [.gitlab-ci-example.yml](.gitlab-ci-example.yml) for the illustrative pipeline implementing all of the above.
