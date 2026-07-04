# Detection, Monitoring & Incident Response — Module 6

There is no centralised detection or alerting today (confirmed directly by F-21 — no `aws_cloudtrail` resource
exists anywhere in the reviewed codebase, not misconfigured, simply absent). This module designs the capability from
zero, then walks a concrete incident through it end-to-end.

## 1. CSPM approach across providers

A single CSPM tool evaluated continuously against all three providers, rather than three separate posture reviews:

- **What it watches:** the same misconfiguration classes found in Module 1 (public storage/database exposure,
  wildcard IAM, open management ports, missing encryption, missing logging) evaluated continuously against the
  *live* environment, not just at pipeline time. This matters because Module 2's pipeline gates only catch drift
  introduced through Terraform — CSPM is what catches a manual console change made outside the pipeline, which is a
  real risk in a 100-workload estate with two account-tier maturity levels.
- **Coverage difference by landing zone tier:** the newer landing-zone-accelerator tier already has continuous
  compliance monitoring switched on — CSPM there is a matter of connecting an existing signal to the centralised
  destination below. The older account-per-environment tier has no equivalent today, so CSPM onboarding there is
  itself a prioritised piece of remediation work, not just a monitoring config change.
- **Same tool, same ruleset logic as the pipeline:** the CSPM policy set should mirror the OPA/Conftest policies from
  Module 2 wherever possible, so "what fails a merge" and "what triggers a live alert" are the same definition of
  bad, not two policies that quietly diverge over time.

## 2. Telemetry: what's collected, where it's centralised, and alert fatigue

| Source | Telemetry collected | Centralised to |
|---|---|---|
| AWS | CloudTrail (management + data events for Restricted-classified resources), VPC Flow Logs, GuardDuty findings | SIEM ingestion pipeline (below) |
| Azure | Azure Activity Log, Diagnostic Settings (NSG flow logs, SQL auditing — closes F-23), Microsoft Defender for Cloud alerts | Same SIEM |
| GCP | Cloud Audit Logs (Admin Activity + Data Access for Restricted resources), VPC Flow Logs, Security Command Center findings | Same SIEM |
| Pipeline (Module 2) | Scan results (Checkov/tfsec/Trivy/OPA), SBOM diffs | Same SIEM, tagged `source: pipeline` — supply-chain and runtime telemetry live in one place, not two dashboards nobody correlates |

**Centralisation target:** one SIEM/log-analytics destination per data-residency boundary (Module 5) — not
necessarily one single global instance, since sovereignty requirements may require regional segregation, but one
per-jurisdiction destination that all three providers' telemetry converges into, so an analyst investigating a
workload never has to context-switch between three separate consoles to build a timeline.

**Alert fatigue management:**
- Alerts are tiered by the same workload-criticality tags used in Module 2/4/5 — a Tier A finding pages on-call
  immediately; the same class of finding on Tier C generates a ticket, not a page.
- Detections are correlated before alerting, not raised per raw event — e.g. "IAM policy modified" alone is noise
  across 100 workloads; "IAM policy modified to add a wildcard action" **and** "that credential used from a new
  source IP within the hour" is a correlated, actionable alert.
- Known-benign, recurring low-severity CSPM findings (Wave 3 in the severity methodology) are suppressed from
  real-time alerting entirely and instead roll up into the findings register on a scheduled cadence — they're still
  tracked, just not competing for attention with something that needs a response in minutes.

## 3. Incident scenario — wildcard CI service account compromised, used to access a database

This is the F-11/F-12 credential from the findings register (a static AWS access key attached to a wildcard IAM
policy), now confirmed compromised and used to reach a database.

**Detection.** The correlated-alert model above fires: CloudTrail shows the CI service account's access key used
from a source IP/ASN inconsistent with GitLab's known runner IP ranges, immediately followed by `rds:DescribeDBInstances`
and a database connection attempt — an access pattern this identity has never previously exhibited. GuardDuty's
`UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration`-class finding (or the equivalent anomalous-use detection)
corroborates it. This is flagged Critical and pages on-call within minutes, not discovered on a monthly log review.

**Containment.** In order, within the first response window:
1. Revoke/rotate the compromised access key immediately (`aws iam update-access-key --status Inactive`, then delete)
   — under the Module 3 redesign this credential shouldn't exist at all, but containment has to assume the estate
   is mid-migration and some workloads haven't been cut over yet.
2. Attach an explicit deny policy to the associated role/user as a second control, in case key deactivation alone
   races with an already-established session.
3. Isolate the targeted database at the network layer (Module 4) — tighten its security group to remove the path
   the compromised credential used, rather than taking the database offline outright, to preserve availability for
   legitimate traffic where possible.
4. Snapshot the database and any affected instance for forensics before any further remediation touches them.

**Eradication.** Confirm via CloudTrail/database audit logs exactly what the credential accessed (which
tables/queries, not just "it connected") to scope the actual data exposure. Rotate any credentials or secrets the
compromised access could have read (this is exactly why F-19's plaintext database password in EC2 user-data
matters — if that pattern exists elsewhere, this incident is the reason to assume it's also compromised and rotate
it too). Confirm no persistence was established (no new IAM users/roles/access keys created using the compromised
credential's permissions — the wildcard policy's `iam:*`-adjacent actions, if present, would have allowed this,
which is itself evidence for why F-11/F-12 needed the Module 3 redesign regardless of this specific incident).

**Recovery.** Restore the security group to its designed state once the compromised path is confirmed closed, bring
the database back to normal operating posture, and re-enable the workload's pipeline access using a freshly-issued,
correctly-scoped credential under the Module 3 model — not the same wildcard policy reinstated under time pressure.

## 4. Communicating up during vs. after the incident

**While unfolding (to the ITSO-equivalent stakeholder):**
- First notification within the containment window above, not after root cause is known — the message is a status,
  not a full explanation: what's confirmed (credential compromised, database access attempted), what's not yet known
  (scope of data accessed), and what containment action is already in progress. The goal is situational awareness
  for a decision-maker, not a technical debrief.
- Short, timed updates (e.g. every 30–60 minutes) through containment and eradication, each one stating what changed
  since the last update — deliberately avoiding jargon-heavy detail that would force the stakeholder to ask
  clarifying questions mid-incident.

**Post-incident report:**
- Full timeline, root cause (the wildcard policy + static credential pattern from F-11/F-12), confirmed scope of
  data accessed, and — critically — the fact that the Module 3 IAM redesign was already planned/underway
  independent of this incident, versus what specifically gets accelerated because of it.
- Named corrective actions with owners and dates, feeding back into the findings register (Module 1) as new/updated
  entries so the incident produces a trackable action, not just a narrative document.
- This is the artefact a governance panel would expect to see referenced in the live presentation (Section 6) as
  evidence that detection and response for the estate's highest-risk finding pattern is a designed capability, not a
  hypothetical.
