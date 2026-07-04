# Remediation Advisory Pack — Module 7

Written for a delivery engineer with no security background. Each section covers one of the three most critical
findings from [01-findings/findings-register.md](../01-findings/findings-register.md). Corrected Terraform for each
is in [fixed-terraform/](fixed-terraform/).

---

## Advisory 1 — Public S3 buckets with no access restriction (F-01, F-02)

### The risk, in plain language

Six storage buckets in this estate have no "public access block" configured — think of it as the door to a storage
room having no lock fitted at all, not a lock left unlocked. One of them (`data`) is explicitly public today; the
other five are one accidental bucket-policy change away from being public too, because the safety catch that would
normally prevent that isn't there. If any of these buckets hold customer or financial records, anyone who finds the
bucket name — which are often guessable or leak through error messages, logs, or search engines — can read or, in
some cases, overwrite the contents without needing any credentials at all.

### Step-by-step remediation

1. Open [fixed-terraform/s3-public-access-block.tf](fixed-terraform/s3-public-access-block.tf) — it adds an
   `aws_s3_bucket_public_access_block` resource for every bucket in `terraform/aws/s3.tf`.
2. Apply it to a non-production copy of the estate first if one exists, and confirm the bucket's existing legitimate
   consumers (application roles, other services) are on the allow-list from Module 3's tag-scoped IAM policies —
   not relying on public access, which they shouldn't be if built correctly.
3. Merge through the pipeline (Module 2) — this is exactly the class of change the pipeline's Checkov gate is
   designed to require going forward, so once this lands, the same misconfiguration can't silently return.
4. Roll out bucket-by-bucket, not as one big-bang change, since each bucket may have different legitimate consumers
   to verify first.

### Evidence the fix is complete

- Re-run `checkov -d terraform/aws --check CKV2_AWS_6` and confirm zero failures on these six buckets.
- AWS Console/CLI: `aws s3api get-public-access-block --bucket <name>` returns all four block settings set to `true`
  for each bucket.
- Confirm via CloudTrail that no `PutBucketPolicy`/`PutBucketAcl` call has re-opened access after the fix — this is
  also now a live CSPM check per Module 6, not just a one-time verification.

---

## Advisory 2 — Database with encryption-at-rest disabled and public accessibility enabled (F-03)

### The risk, in plain language

The application database is configured two ways that should never be combined: it's reachable directly from the
internet (`publicly_accessible = true`), and everything stored in it is unencrypted (`storage_encrypted = false`).
Individually, either is a real gap; together, they mean that anyone who can reach the database's network address —
and it's reachable from anywhere, not just from inside the application — can attempt to connect to it directly, and
if they succeed, everything they read is in plain, unencrypted form. It also has no backup retention
(`backup_retention_period = 0`) and skips a final snapshot on deletion, so there's currently no recovery path if the
data is destroyed, whether by attack or accident.

### Step-by-step remediation

1. Apply [fixed-terraform/rds-encrypted-private.tf](fixed-terraform/rds-encrypted-private.tf), which sets
   `storage_encrypted = true` with a customer-managed KMS key (per Module 5), sets `publicly_accessible = false`,
   sets a real `backup_retention_period`, and removes `skip_final_snapshot`.
2. **Important operational note:** `storage_encrypted` cannot be changed on an existing running RDS instance — AWS
   requires creating an encrypted snapshot/copy and restoring into a new instance. This is a maintenance-window
   change, not a hot config update; plan a cutover window and confirm the application's connection string/DNS
   updates to point at the new instance.
3. Confirm no application or CI component depends on reaching this database from outside the VPC before removing
   public accessibility — check security group references and any hardcoded public endpoint in application config
   (see F-19's plaintext user-data password — that same file references `aws_db_instance.default.endpoint`, so
   confirm the app is using the private endpoint after cutover, not a cached public one).

### Evidence the fix is complete

- `aws rds describe-db-instances` shows `StorageEncrypted: true` and `PubliclyAccessible: false` for the instance.
- `checkov --check CKV_AWS_16,CKV_AWS_17` returns zero failures for this resource.
- A connection attempt from outside the VPC/allow-listed security group is confirmed to fail (test from a host that
  is deliberately not on the allow-list).
- Backup retention is confirmed non-zero and a manual snapshot restore is test-run at least once before sign-off.

---

## Advisory 3 — Wildcard-permission IAM policy on a long-lived service credential (F-11, F-12)

### The risk, in plain language

Two separate IAM policies in this estate grant near-total account permissions (`ec2:*`, `s3:*`, `lambda:*`, `rds:*`,
all on "any resource") to identities that don't need anywhere near that much access to do their actual job. One of
them is attached to a **static, long-lived access key** — the cloud equivalent of a master key that never expires
and was never designed to be rotated. If that credential is ever leaked (committed to a repo, logged accidentally,
phished from a build log), whoever has it can act as if they were a full administrator of this account — not just
of the one thing they were supposed to manage.

### Step-by-step remediation

1. Apply [fixed-terraform/iam-scoped-policy.tf](fixed-terraform/iam-scoped-policy.tf), which replaces both wildcard
   policies with the tag-scoped, resource-constrained policy designed in
   [03-identity-governance/cross-cloud-iam-design.md](../03-identity-governance/cross-cloud-iam-design.md).
2. Remove the static IAM user and its access key (`aws_iam_user.user`, `aws_iam_access_key.user`) entirely — replace
   CI authentication with the OIDC-federated role from Module 3. This is the single highest-value change in this
   advisory: a scoped policy on a credential that never expires is still a standing risk; removing the standing
   credential closes the issue at its root.
3. Tag every resource this pipeline manages with the `workload-id` tag the new policy's conditions key off — the
   scoped policy will silently deny access to untagged resources, so tagging has to land first or the pipeline will
   break on the next run.
4. Test the new role/policy against a non-production apply before cutting production pipelines over.

### Evidence the fix is complete

- `aws iam list-access-keys --user-name <user>` returns empty / the user no longer exists.
- `checkov --check CKV_AWS_355,CKV_AWS_290,CKV_AWS_289,CKV_AWS_287,CKV_AWS_288` returns zero failures on the
  replacement policy resources.
- A test pipeline run against a resource **without** the `workload-id` tag matching is confirmed to fail with an
  access-denied error — proving the scoping is actually enforced, not just present in the policy document.
- CloudTrail shows all subsequent CI activity authenticated via the federated role (`AssumedRoleWithWebIdentity`),
  with no further `sts:GetSessionToken`/long-lived-key-based calls from this pipeline.
