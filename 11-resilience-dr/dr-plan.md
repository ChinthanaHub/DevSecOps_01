# Resilience & Disaster Recovery Across Clouds — Module 13

Security assurance that ignores availability is incomplete — several of this review's own findings (F-25, F-26: no
backup retention, no multi-AZ, no Cloud SQL backups) are availability gaps discovered through a security lens, and
they need a resilience answer, not just a "turn a setting on" answer.

## 1. RTO/RPO for a representative workload

**Workload:** the AWS web application + RDS database workload from Module 9's threat model — chosen because it's
representative of the estate's largest category (storage- and database-backed web apps), and because F-25 already
shows it currently has no recovery capability at all (`backup_retention_period = 0`, `multi_az = false`,
`skip_final_snapshot = true`).

| Target | Value | Why this figure |
|---|---|---|
| **RTO** (Recovery Time Objective) | 4 hours | This is an internal-facing operational application, not a public safety-critical system — 4 hours balances a realistic engineering response window against not leaving the estate exposed indefinitely. A tighter RTO (e.g. sub-15-minutes) would require active-active multi-AZ with automated failover already running continuously, which is a meaningfully higher operating cost than this workload's criticality justifies. |
| **RPO** (Recovery Point Objective) | 15 minutes | Achievable with RDS automated backups + transaction log shipping (point-in-time recovery), without needing synchronous cross-region replication. |

**Architecture choices this target actually requires** (not just "enable backups" — the target drives specific
decisions):

- `multi_az = true` (fixes F-25 directly) — this is what makes the 4-hour RTO achievable at all; without it, recovery
  means restoring from a snapshot into a brand-new instance, which routinely takes longer than 4 hours for a
  production-sized database once DNS/connection-string cutover is included.
- Automated backups with point-in-time recovery enabled and a retention period covering at least the RPO window with
  margin (14 days, matching the fix already specified in
  [07-remediation/fixed-terraform/rds-encrypted-private.tf](../07-remediation/fixed-terraform/rds-encrypted-private.tf)).
- A tested (not just configured) restore runbook — an RTO target that's never been exercised is an assumption, not a
  capability. This is listed as a required verification step, not assumed to work because the setting is correctly
  configured.
- The application tier (EC2 web hosts) needs to be re-creatable from the pipeline (Module 2) within the same RTO
  window — which is only true if the Terraform for this workload is complete and current in Git, tying this
  directly to the Git-recoverability question below.

## 2. Backup approach across resource types

| Resource type | Backup approach | Encryption & access control |
|---|---|---|
| **Object storage** (S3 / Azure Storage / GCS) | Versioning enabled (fixes F-27) + cross-region replication for Restricted-classified buckets only, not universally — replication for every bucket in a 100-workload estate is cost without proportionate benefit for Public/Internal-classified data. | Replicated copies use the same per-workload CMK model as the primary (Module 5) — a backup that's encrypted with a different, less-controlled key is a second, quieter place the data can leak from. Access to backup/replica buckets is scoped by the same tag-based IAM policy as the primary (Module 3), not left more permissive "because it's just a backup." |
| **Managed databases** (RDS / Azure SQL / Cloud SQL) | Automated backups + point-in-time recovery, retention tuned per workload's RPO (14 days minimum for Restricted-classified data, per the representative workload above). Fixes F-25 (RDS) and F-26 (`google_sql_database_instance.master_instance` backup_configuration.enabled = false) directly. | Snapshots inherit the source database's encryption (this is precisely why F-03/F-07's fix — enabling `storage_encrypted` — has to land before backups are meaningful; an unencrypted database produces unencrypted snapshots regardless of any backup policy layered on top). Snapshot access restricted to the same workload-tagged role as the live database, not broader. |
| **Compute** (EC2 / VM instances) | Not backed up as stateful entities at all — application-tier compute in this estate is intentionally treated as disposable and re-creatable from the pipeline (Module 2) plus a golden AMI/image pipeline, rather than snapshotted. Any state living only on a compute instance's local disk (a risk in itself) should be flagged as its own finding, not backed up in place. | N/A directly — the golden image build pipeline is scoped by the same IAM model as any other pipeline job. |

## 3. Is cross-cloud failover realistic for this estate?

**Position: no, not as a general strategy — resilience is better addressed within a single provider per workload,
with cross-cloud reserved for a small, explicitly justified subset.** This is worth arguing rather than assuming,
since "multi-cloud" in the roadmap could easily be misread as "multi-cloud DR everywhere":

- Cross-cloud failover requires the application and data layer to be portable in ways this estate isn't designed
  for today — the workloads reviewed use provider-native managed services (RDS, Cloud SQL, Azure SQL) with no
  cross-provider equivalent API. Building and maintaining a cross-cloud-compatible data layer for ~100 workloads,
  most of which are ordinary storage/database-backed web apps, is a substantial and ongoing engineering cost that
  doesn't match the actual risk being defended against (a full provider-region outage is rare relative to the
  far more common failure modes — misconfiguration, credential compromise, human error — this whole review is
  actually about).
- The realistic risk cross-cloud DR would address (an entire cloud provider becoming unavailable) is already
  substantially mitigated **within** a single provider via multi-region failover, which is dramatically simpler to
  build, test, and actually trust under pressure than a cross-provider equivalent.
- Where cross-cloud resilience genuinely earns its cost: workloads whose unavailability would be a **programme-level**
  failure, not a workload-level one (e.g. whatever hosts the identity federation trust root from Module 3, or the
  centralised SIEM destination from Module 6 — if detection itself goes down during a provider outage, that's a
  compounding failure). These are the exception, sized in the single digits, not the default posture for the estate.

## 4. Full account/subscription/project rebuild — what's recoverable from Git vs. lost

This is where the pipeline design (Module 2) and commit hygiene (Section 4.3) directly determine the disaster
recovery posture, not just code quality:

**Recoverable purely from Git:**
- All infrastructure topology — networks, security groups/NSGs, IAM roles/policies, compute definitions, storage
  bucket configuration — since it's all Terraform, and Terraform is the only way resources are meant to reach this
  estate under the Module 2 pipeline design.
- The policy-as-code rules (Module 2/10) and pipeline configuration itself — a rebuilt account gets the same guardrails
  re-applied automatically on first pipeline run, not manually reconstructed from memory.

**Not recoverable from Git — genuinely lost or requiring a separate recovery path:**
- Actual data (database contents, object storage contents) — this is why the backup approach above has to exist
  independently of Git; Terraform re-creates an empty, correctly-configured database, not its contents.
- Any manually-applied configuration made outside the pipeline (exactly the drift risk Module 6's CSPM is designed
  to catch continuously) — if such drift existed and was never reconciled back into Terraform, it's lost on rebuild,
  which is itself an argument for why CSPM matters for resilience, not just security posture.
- Provider-side account/subscription/project identifiers themselves and any state that references them by ID rather
  than name (Terraform state files need to be restorable from the state backend — which is why the state backend's
  own backup, e.g. S3 versioning on `tf-state-*` buckets, is part of this plan too, not an afterthought).
- Secrets and credentials — deliberately never in Git (commit hygiene requirement, Section 4.3) — must be
  re-provisioned from the secrets manager's own backup/replication, not reconstructed from the Terraform history.

**Overall assessment:** for a workload built cleanly under the Module 2 pipeline from day one, the *shape* of the
estate is close to fully recoverable from Git; the *contents* are only as recoverable as the backup approach above,
and any workload with undocumented manual drift is the actual gap — which is a strong, concrete argument for why
Module 6's continuous CSPM coverage extending to the older, currently-unmonitored landing zone tier is a resilience
priority, not just a detection one.
