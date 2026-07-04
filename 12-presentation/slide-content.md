# Presentation Content — 14 Slides

Script/content for the 25-minute presentation portion of the Section 6 live session. Each slide below is written
so it can be dropped almost directly into PowerPoint/Google Slides — the **On-slide bullets** are what goes on the
slide itself; the four labelled sections underneath are speaker-note detail, not extra slide text.

Diagram slides (10–11) reference Modules 11/12, which are still pending — placeholder call-outs are marked
`[DIAGRAM PENDING]` so nothing here blocks building the deck now and dropping the images in later.

---

## Slide 1 — Title & Agenda

**On-slide bullets**
- DevSecOps Engineer Technical Assessment — Track 2: Multi-Cloud Platform Security & Compliance
- [Your name] · [Date] · Live governance panel review
- Agenda: risk posture → findings & prioritisation → identity/network/data as one design → target architecture →
  the one risk we need this panel to accept → what happens next

---

## Slide 2 — Executive Summary: Overall Risk Posture

**On-slide bullets**
- Reviewed against a public reference environment standing in for the ~100-workload estate — high-risk-by-default,
  concentrated in a small number of *repeating patterns*, not 27 unrelated one-offs
- No evidence of exploitation — this is a design review of what's possible today, not an incident report
- One finding cannot be fully closed before go-live (a COTS vendor limitation) — handled as a formal risk decision,
  not left as a silent gap

1) **Summary** — The estate's risk is real but patterned: the same "no public access control" and "wildcard
   permission" shapes recur across storage, database, and identity resources. Fix the pattern once, not 27 times.
2) **How to identify** — Static IaC scanning (Checkov, tfsec) plus a dedicated secrets scan (Gitleaks) run against
   the full reviewed codebase; 477 raw failed checks, curated to the 27 most representative.
3) **What is the outcome** — A prioritised, defensible remediation programme instead of an undifferentiated list of
   477 alerts — leadership gets a small number of decisions to make, not 477.
4) **Reference** — [README.md](../README.md) Executive Summary; [01-findings/findings-register.md](../01-findings/findings-register.md)

---

## Slide 3 — Assessment Scope & Methodology

**On-slide bullets**
- Reference repo: `bridgecrewio/terragoat` — deliberately vulnerable, spans AWS + Azure + GCP in one repo
- Tools run: Checkov 3.3.6 (IaC + secrets), tfsec (cross-check), Gitleaks 8.21.2 (dedicated secrets scan)
- 477 failed checks captured; every finding in this deck is cited by exact file:line, not paraphrased

1) **Summary** — The review was run the way the real estate's pipeline should run it: automated scanners against
   real IaC, not a manual checklist.
2) **How to identify** — Command-level: `checkov -d . --output json`, `tfsec . --format json`,
   `gitleaks detect --source . --no-git`. Versions and exact commands are logged for repeatability.
3) **What is the outcome** — Every finding in this submission is reproducible by anyone with the same repo and the
   same three commands — no finding here is a one-off manual observation.
4) **Reference** — [README.md](../README.md) "Tooling used"; [01-findings/findings-register.md](../01-findings/findings-register.md) tool table

---

## Slide 4 — Findings Landscape: 27 Findings Across 3 Clouds

**On-slide bullets**
- 27 curated findings spanning storage, database, IAM, network, secrets, logging, backup/resilience
- Same misconfiguration shape shows up on more than one provider — e.g. open management ports on both an AWS
  security group *and* an Azure NSG
- This cross-provider repetition is itself a finding: today's review process doesn't yet catch a pattern once and
  apply it everywhere

1) **Summary** — Breadth matters as much as depth here — every required finding category has at least one AWS,
   Azure, or GCP example, because the roadmap adds two more providers this year.
2) **How to identify** — Curated from the 477 raw scanner results by mapping each to the six required finding
   categories and picking the clearest, most representative example(s) per category.
3) **What is the outcome** — Confidence that the review process (not just this one pass) will hold up once Azure/GCP
   workloads are live, because the same tooling already caught issues on all three providers in one run.
4) **Reference** — [01-findings/findings-register.md](../01-findings/findings-register.md) sections A–G

---

## Slide 5 — Top 3 Critical Findings (Deep Dive)

**On-slide bullets**
- **F-01/F-02** — Six storage buckets with no public access block; one is explicitly public today
- **F-03** — Application database: encryption-at-rest disabled *and* public network access enabled, simultaneously
- **F-11/F-12** — Two independent wildcard IAM policies (`Resource:"*"`), one on a static, long-lived access key

1) **Summary** — These three are the ones that would put the programme back in the position the original internal
   audit found it in — public exposure, unencrypted sensitive data, an unbounded credential.
2) **How to identify** — `CKV2_AWS_6` (public access block), `CKV_AWS_16`/`CKV_AWS_17` (encryption + public access),
   `CKV_AWS_355`/`CKV_AWS_290` (wildcard IAM) — all reproducible via Checkov against the reviewed repo.
3) **What is the outcome** — Fixed with concrete, ready-to-apply Terraform (not just a recommendation) — see the
   remediation pack. Two of three are one-line/one-resource changes; the RDS fix needs a planned maintenance window.
4) **Reference** — [01-findings/findings-register.md](../01-findings/findings-register.md) F-01/F-02/F-03/F-11/F-12;
   [07-remediation/remediation-advisory.md](../07-remediation/remediation-advisory.md);
   [07-remediation/fixed-terraform/](../07-remediation/fixed-terraform/)

---

## Slide 6 — Prioritisation Logic: Why These, Why Now

**On-slide bullets**
- Severity = exposure × data sensitivity × exploitability × blast radius — not just "what the scanner labelled
  Critical"
- Landing-zone tier matters: the same finding in the older account-per-environment tier outranks it in the newer,
  continuously-monitored tier, because there's no compensating control there yet
- A *recurring* pattern (e.g. the same missing control on six buckets) is fixed once at the pipeline/policy layer,
  not six times by hand

1) **Summary** — With ~100 workloads and limited remediation bandwidth, the question was never "what's broken" —
   it's "what gets fixed first, and what gets formally accepted as risk instead."
2) **How to identify** — A four-factor severity rubric plus a three-lens prioritisation model (landing zone tier,
   recurrence, fix cost vs. risk-acceptance cost), applied consistently to every finding.
3) **What is the outcome** — A defensible answer to "why did you fix this and not that" under panel questioning —
   the logic is written down, not judgment-call-by-feel.
4) **Reference** — [01-findings/severity-methodology.md](../01-findings/severity-methodology.md)

---

## Slide 7 — Identity Governance: Closing the Standing-Credential Gap

**On-slide bullets**
- No long-lived cross-cloud credentials, anywhere — OIDC workload identity federation for every pipeline
- Standing human access = read-only; privileged access is time-bound and approval-gated, never standing
- The wildcard CI credential (F-11/F-12) redesigned with a tag-scoped policy — a compromised token now reaches
  *one* tagged workload, not the whole account

1) **Summary** — One governance model, three provider-native implementations — not three separate IAM strategies
   that quietly drift apart.
2) **How to identify** — Directly driven by F-11/F-12/F-18: a static access key with a wildcard policy is the exact
   shape of the scenario's original audit finding.
3) **What is the outcome** — Blast radius from a leaked/compromised pipeline credential shrinks from "the whole AWS
   account" to "one workload, for a few hours at most."
4) **Reference** — [03-identity-governance/cross-cloud-iam-design.md](../03-identity-governance/cross-cloud-iam-design.md)

---

## Slide 8 — Network Zero-Trust: Segmentation as the Second Layer

**On-slide bullets**
- Four sensitivity tiers — Edge / Application / Data / Management — same model on every cloud provider
- Data-tier resources: no public IP, inbound only from the Application tier by reference, default-deny egress
- Fixes the open-port pattern found on *both* AWS (F-14) and Azure (F-16) with one shared design, not two fixes

1) **Summary** — Identity controls who can act; network controls what can reach what — the database in F-03 should
   never have been reachable from the internet in the first place, independent of its access-control settings.
2) **How to identify** — F-14 (AWS security group open on 22/80), F-16 (Azure NSG open on 22/3389), F-15
   (unrestricted database egress) — same misconfiguration shape, two providers.
3) **What is the outcome** — A workload's tier — not which cloud it's on — determines its exposure. Removes the risk
   of three separate, drifting network philosophies once Azure/GCP onboard.
4) **Reference** — [04-network-zero-trust/network-design.md](../04-network-zero-trust/network-design.md)

---

## Slide 9 — Data Protection: The Third Pillar, Tied Together

**On-slide bullets**
- Per-cloud-native KMS, not one centralised key store — smaller blast radius if a single key is compromised
- Data classification (Public / Internal / Restricted) drives which controls apply — not every workload gets the
  same treatment
- **This is the "one story," not three modules:** a Data-tier resource (network) is the same resource getting
  workload-tagged encryption (data protection) and the same resource whose access policy was scoped by tag
  (identity)

1) **Summary** — Identity, network, and data protection share one tagging model — a workload's tier and
   classification drive its access policy, its network placement, *and* its encryption posture, in one pass.
2) **How to identify** — F-03/F-07 (no KMS key referenced at all on the primary database) and F-10 (encryption
   present on one bucket but not its sibling holding more sensitive data) — a control that existed but wasn't
   applied consistently.
3) **What is the outcome** — A key compromise on one provider doesn't cascade estate-wide; a workload's
   classification, not manual judgement, decides whether BYOK/HYOK is even a conversation worth having.
4) **Reference** — [05-data-protection/encryption-key-mgmt.md](../05-data-protection/encryption-key-mgmt.md)

---

## Slide 10 — Target-State Architecture: HLD Walkthrough

**On-slide bullets**
- `[DIAGRAM PENDING — Module 11 HLD to be inserted here]`
- System-context view: source control/CI → landing zone(s) → identity provider → secrets/key management →
  logging/monitoring destination → external edge
- Trust boundaries and environment boundaries marked explicitly, not implied by box placement

1) **Summary** — One-page view a non-technical stakeholder can follow: what talks to what, and where the trust
   boundaries actually sit.
2) **How to identify** — Built from Modules 1–10 collectively — every major building block on this diagram maps to
   a design decision already walked through in this deck.
3) **What is the outcome** — A shared reference point the whole programme — not just this review — can use when
   reasoning about where a new workload or a new provider fits.
4) **Reference** — `10-architecture/hld-diagram.*` (pending) + `10-architecture/architecture-narrative.md` (pending)

---

## Slide 11 — Target-State Architecture: LLD Walkthrough

**On-slide bullets**
- `[DIAGRAM PENDING — Module 12 LLD to be inserted here]`
- One representative slice, expanded: ingress → application tier → database, including the CI/CD path that
  provisions it
- Specific IAM roles, specific permissions, where encryption happens, where the pipeline and detection tooling
  physically sit

1) **Summary** — This is the diagram an engineer could actually build from — the HLD is for the panel, this one's
   for delivery.
2) **How to identify** — Expands the exact workload used throughout this deck (the web+DB workload from the threat
   model) down to subnet/role/port level.
3) **What is the outcome** — Removes ambiguity for delivery engineers implementing the target state — no
   interpretation gap between "the design" and "what got built."
4) **Reference** — `10-architecture/lld-diagram.*` (pending); [08-threat-model/threat-model.md](../08-threat-model/threat-model.md) (same workload)

---

## Slide 12 — The COTS Exception: Compensating Controls & the Risk Decision for This Panel

**On-slide bullets**
- Financial reconciliation tool's driver cannot operate with storage encryption enabled — confirmed vendor
  limitation, not a config gap
- Compensating controls: strictest network isolation in the estate, Tier-A detection coverage regardless of actual
  criticality, encryption at every other layer the driver doesn't block, dual-approval JIT access
- **Residual risk: High (not Critical, not Medium)** — this is the one decision we need this panel to formally accept

1) **Summary** — We're not asking you to accept "no controls" — we're asking you to accept a named, bounded risk
   with four specific compensating controls and a re-review date attached.
2) **How to identify** — Directly from the scenario's stated constraint; verified against Module 5's classification
   model (this data is Restricted, so the gap is real, not incidental).
3) **What is the outcome** — A time-bound interim state with a named target state (vendor fix or re-platform), and
   three explicit guardrails preventing this exception from being cited to justify others across the estate.
4) **Reference** — [07-remediation/compensating-controls.md](../07-remediation/compensating-controls.md)

---

## Slide 13 — What the First 30/60/90 Days Look Like

**On-slide bullets**
- **Days 1–30:** Land the Wave 1 fixes (public buckets, RDS encryption cutover, wildcard IAM removal) through the
  pipeline gates in Module 2 — not by hand
- **Days 30–60:** Stand up centralised detection (Module 6) on the older landing-zone tier first, since it has zero
  coverage today
- **Days 60–90:** Extend the identity/network/data model to the first Azure or GCP pilot workload, proving the
  design travels before the full onboarding wave

1) **Summary** — The first stretch of time is about proving the pattern-based fixes work at pipeline scale, not
   re-doing the review — the review is done; the next phase is operationalising it.
2) **How to identify** — Sequenced directly off the severity methodology's Wave 1/2/3 model and the compliance
   deadline constraint from the business scenario.
3) **What is the outcome** — A credible, dated delivery plan the panel can hold this programme to — not a vague
   commitment to "get to it."
4) **Reference** — [01-findings/severity-methodology.md](../01-findings/severity-methodology.md) (wave model);
   [02-pipeline-supply-chain/pipeline-design.md](../02-pipeline-supply-chain/pipeline-design.md)

---

## Slide 14 — Quick Action: Remediation Plan Summary (Closing Slide)

*Deliberately high-level — detail lives in the modules, not here.*

**On-slide bullets**
- **Fix now (Wave 1):** public storage buckets · RDS encryption + private access · wildcard IAM removal · secrets
  scan gate in the pipeline
- **Accept as bounded risk:** COTS encryption gap — compensating controls in place, panel sign-off requested today
- **Stand up next:** centralised logging/detection · OPA policy gate · tiered pipeline enforcement across all ~100
  workloads
- **Prove out before full rollout:** the identity/network/data model on one Azure or GCP pilot workload

**Ask of this panel:** formal acceptance of the COTS residual risk (Slide 12), and sign-off to begin Wave 1 remediation
through the pipeline design in Module 2.
