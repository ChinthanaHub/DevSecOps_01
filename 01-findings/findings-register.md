# Findings Register — Module 1

**Reference repository:** [bridgecrewio/terragoat](https://github.com/bridgecrewio/terragoat) (forked/cloned for this
review — spans AWS, Azure, and GCP Terraform, which fits the multi-cloud direction of this track directly).

**Tooling used, exact versions run:**

| Tool | Version | Scope |
|---|---|---|
| Checkov | 3.3.6 | IaC misconfiguration + embedded secrets scan (`checkov -d . --output json`) |
| tfsec | latest (aquasecurity) | IaC misconfiguration, cross-checked against Checkov to catch anything Checkov's ruleset missed |
| Gitleaks | 8.21.2 | Git-history secret scanning (`gitleaks detect --source . --no-git`) |

Raw scan output: 477 failed Checkov checks (467 Terraform, 5 secrets, 2 Dockerfile, 3 GitHub Actions), across AWS,
Azure, GCP, and Alibaba Cloud resources. The table below is a curated subset — at least 20 findings as required,
selected to cover every required category and to mirror the four audit findings from the business scenario with a
same-shape example in this codebase, plus additional findings the scenario's 12-workload sample wouldn't have caught.

Every row is a real, reproducible finding — file path and line range are from this repo, not illustrative.

## Legend

Severity per [severity-methodology.md](severity-methodology.md). **Wave** = remediation wave (1 = before go-live,
2 = accepted risk / scheduled in-programme, 3 = backlog/hygiene).

## A. Public data exposure (storage & database)

| ID | Cloud | Resource | Finding | Evidence | Severity | Wave |
|---|---|---|---|---|---|---|
| F-01 | AWS | `aws_s3_bucket.data` — [terraform/aws/s3.tf:1](../reference-repos/terragoat/terraform/aws/s3.tf) | Bucket has no public access block; source comment literally states "bucket is public" | Checkov `CKV2_AWS_6` | Critical | 1 |
| F-02 | AWS | `aws_s3_bucket.financials`, `.operations`, `.data_science`, `.logs` — s3.tf | Same public-access-block gap across four more buckets — a repeated pattern, not an isolated miss | Checkov `CKV2_AWS_6` | High | 1 |
| F-03 | AWS | `aws_db_instance.default` — [terraform/aws/db-app.tf:1-42](../reference-repos/terragoat/terraform/aws/db-app.tf) | `storage_encrypted = false` **and** `publicly_accessible = true` set simultaneously — the exact pairing from the business scenario's audit finding | Checkov `CKV_AWS_16`, `CKV_AWS_17` | Critical | 1 |
| F-04 | GCP | `google_sql_database_instance.master_instance` — [terraform/gcp/big_data.tf:1-19](../reference-repos/terragoat/terraform/gcp/big_data.tf) | `authorized_networks` set to `0.0.0.0/0`, no `require_ssl`, `backup_configuration.enabled = false` — the AWS database finding's exact GCP-shaped equivalent | Checkov `CKV_GCP_11`, `CKV_GCP_60`, `CKV_GCP_6`, `CKV_GCP_14` | Critical | 1 |
| F-05 | Azure | `azurerm_storage_account.security_storage_account`, `.example` — [terraform/azure/storage.tf](../reference-repos/terragoat/terraform/azure/storage.tf), [mssql.tf](../reference-repos/terragoat/terraform/azure/mssql.tf) | Public network access not disabled; TLS minimum version not pinned to 1.2 | Checkov `CKV_AZURE_59`, `CKV_AZURE_44` | High | 1 |
| F-06 | GCP | `google_bigquery_dataset.dataset` — big_data.tf:21-37 | Dataset ACL grants `READER` to `allAuthenticatedUsers` — effectively any Google-authenticated principal, not just this project's team | Checkov `CKV_GCP_15` | High | 1 |

## B. Encryption at rest / in transit & key management

| ID | Cloud | Resource | Finding | Evidence | Severity | Wave |
|---|---|---|---|---|---|---|
| F-07 | AWS | `aws_db_instance.default` — db-app.tf:19 | No KMS key referenced anywhere in the resource — encryption isn't just misconfigured, key management was never designed in | Checkov `CKV_AWS_16` | Critical | 1 |
| F-08 | Azure | `azurerm_mssql_server` family — mssql.tf | TLS minimum version and Azure AD-only auth not enforced on the SQL server | Checkov `CKV_AZURE_52`, `CKV2_AZURE_27` | High | 2 |
| F-09 | GCP | `google_bigquery_dataset.dataset` — big_data.tf:21-37 | Not encrypted with a Customer-Supplied/Customer-Managed key — falls back to Google-managed keys with no customer-controlled blast-radius boundary | Checkov `CKV_GCP_81` | Medium | 2 |
| F-10 | AWS | `aws_s3_bucket.financials` (holds `customer-master.xlsx`) — s3.tf:42 | No `server_side_encryption_configuration` block at all, unlike the sibling `logs` bucket which correctly uses a KMS CMK — proves the pattern is known-good elsewhere but inconsistently applied | Checkov (bucket lacks `CKV_AWS_145`-passing config) | High | 1 |

## C. IAM least-privilege violations

| ID | Cloud | Resource | Finding | Evidence | Severity | Wave |
|---|---|---|---|---|---|---|
| F-11 | AWS | `aws_iam_user_policy.userpolicy` on `aws_iam_user.user` (has a **long-lived** `aws_iam_access_key`) — [terraform/aws/iam.tf:25-46](../reference-repos/terragoat/terraform/aws/iam.tf) | Policy grants `ec2:*`, `s3:*`, `lambda:*`, `cloudwatch:*` on `Resource: "*"`, attached to a static access key — this is the direct shape of the "wildcard-permission CI service account" from the business scenario | Checkov `CKV_AWS_355`, `CKV_AWS_290`, `CKV_AWS_289` | Critical | 1 |
| F-12 | AWS | `aws_iam_role_policy.ec2policy` on `aws_iam_role.ec2role` — [terraform/aws/db-app.tf:206-226](../reference-repos/terragoat/terraform/aws/db-app.tf) | Second, independent wildcard policy (`s3:*`, `ec2:*`, `rds:*` on `Resource:"*"`) attached to the EC2 instance profile the database-hosting instance actually runs as | Checkov `CKV_AWS_355`, `CKV_AWS_287`, `CKV_AWS_288` | Critical | 1 |
| F-13 | AWS | `aws_instance.db_app`, `aws_instance.web_host` — db-app.tf:243, ec2.tf:1 | IMDSv1 not disabled — any SSRF on the app served by these instances (see F-19) can pivot straight to the wildcard role credentials above via the metadata endpoint | Checkov `CKV_AWS_79` | High | 1 |

## D. Compute / network exposure

| ID | Cloud | Resource | Finding | Evidence | Severity | Wave |
|---|---|---|---|---|---|---|
| F-14 | AWS | `aws_security_group.web-node` — [terraform/aws/ec2.tf:77-115](../reference-repos/terragoat/terraform/aws/ec2.tf) | Ingress open on port 22 (SSH) and port 80 from `0.0.0.0/0` | Checkov `CKV_AWS_24`, `CKV_AWS_260` | Critical | 1 |
| F-15 | AWS | `aws_security_group_rule.egress` (RDS SG) — db-app.tf:145-152 | Unrestricted egress, all protocols, to `0.0.0.0/0` from the database security group — no egress control at all for a data-tier resource | Checkov `CKV_AWS_23`/manual review (no dedicated unrestricted-egress check fired, but confirmed by inspection) | High | 2 |
| F-16 | Azure | `azurerm_network_security_group.bad_sg` — [terraform/azure/networking.tf:69-107](../reference-repos/terragoat/terraform/azure/networking.tf) | Explicit `AllowSSH` (22) and `AllowRDP` (3389) rules, `source_address_prefix = "*"` — same misconfiguration shape as F-14, different provider syntax, confirming this is a control-translation gap, not a one-off | Checkov `CKV_AZURE_9`, `CKV_AZURE_10` | Critical | 1 |
| F-17 | GCP | `google_compute_instance.server` — terraform/gcp/instances.tf:3-34 | IP forwarding enabled with no documented requirement — widens the instance's blast radius if compromised (can route/relay traffic) | Checkov `CKV_GCP_36` | Medium | 2 |

## E. Hardcoded credentials / secrets in code

| ID | Cloud | Resource | Finding | Evidence | Severity | Wave |
|---|---|---|---|---|---|---|
| F-18 | AWS | [terraform/aws/ec2.tf:15-17](../reference-repos/terragoat/terraform/aws/ec2.tf), [lambda.tf:45](../reference-repos/terragoat/terraform/aws/lambda.tf), [providers.tf:10](../reference-repos/terragoat/terraform/aws/providers.tf) | Literal AWS access key patterns committed in three separate files | Checkov `CKV_SECRET_2` (secrets scan), corroborated by Gitleaks | Critical | 1 |
| F-19 | AWS | `aws_instance.db_app` `user_data` — db-app.tf:243-413 | Database password interpolated in plaintext into EC2 user-data (`DB_PASSWORD` written straight into a PHP include file on disk) — readable by anything with instance/console access, and by anyone who can call `DescribeInstanceAttribute` | Manual review (user_data is visible in the AMI console + via the EC2 API to any principal with `ec2:DescribeInstances`) | High | 1 |
| F-20 | Azure | [terraform/azure/sql.tf:15](../reference-repos/terragoat/terraform/azure/sql.tf) | High-entropy base64 string matching a credential pattern committed alongside the SQL server resource | Checkov `CKV_SECRET_6` | High | 1 |

## F. Logging / audit trail gaps

| ID | Cloud | Resource | Finding | Evidence | Severity | Wave |
|---|---|---|---|---|---|---|
| F-21 | AWS | Entire `terraform/aws/` tree | No `aws_cloudtrail` resource defined anywhere in the codebase — not misconfigured, **absent**. Matches the scenario's "no centralised detection or alerting" directly | Manual review (`grep -r cloudtrail` returns zero matches) | Critical | 1 |
| F-22 | AWS | All six S3 buckets in s3.tf | Access logging (`CKV_AWS_18`) missing on `data`, `financials`, `operations`, `logs`; only `data_science` correctly logs to the `logs` bucket — again, the good pattern exists once and wasn't propagated | Checkov `CKV_AWS_18` | Medium | 2 |
| F-23 | Azure | Azure SQL server resources — mssql.tf | Auditing not enabled, and where present, retention below 90 days | Checkov `CKV_AZURE_23`, `CKV_AZURE_24` | High | 1 |
| F-24 | GCP | `google_sql_database_instance.master_instance` — big_data.tf | pgAudit and connection/disconnection/statement logging flags all unset | Checkov `CKV_GCP_110`, `CKV_GCP_52`, `CKV_GCP_53`, `CKV_GCP_111` | Medium | 2 |

## G. Backup / resilience posture

| ID | Cloud | Resource | Finding | Evidence | Severity | Wave |
|---|---|---|---|---|---|---|
| F-25 | AWS | `aws_db_instance.default` — db-app.tf:16-20 | `backup_retention_period = 0`, `skip_final_snapshot = true`, `multi_az = false` — no recoverability path at all for the primary application database | Checkov `CKV_AWS_133`, manual review | High | 2 (see [11-resilience-dr/dr-plan.md](../11-resilience-dr/dr-plan.md)) |
| F-26 | GCP | `google_sql_database_instance.master_instance` — big_data.tf:15-17 | `backup_configuration.enabled = false` | Checkov `CKV_GCP_14` | High | 2 |
| F-27 | AWS | `aws_s3_bucket.data`, `.financials` — s3.tf | No versioning enabled — a bucket also missing a public access block (F-01/F-02) with no versioning means an accidental or malicious overwrite/delete is unrecoverable | Checkov `CKV_AWS_21` | Medium | 3 |

## Coverage check against Module 1 requirements

- ✅ 27 findings (exceeds the 20 minimum)
- ✅ Spans AWS, Azure, and GCP
- ✅ Covers storage, database, IAM, compute/network, secrets, logging, and backup/resilience
- ✅ Includes at least one same-control-different-provider comparison per category where the repo supports it (F-01/F-04/F-05 for storage/DB exposure; F-11/F-12 vs F-16 for wildcard/permissive-by-default patterns; F-14 vs F-16 for open management ports)
- ✅ Directly mirrors all four of the business scenario's original audit findings (public storage → F-01/F-02; unencrypted+public DB → F-03/F-04; wildcard CI-style service account → F-11/F-12; inconsistent/absent logging → F-21/F-23/F-24), plus surfaces additional issues (F-13, F-19, F-25–27) the scenario's 12-workload sample wouldn't have caught

Prioritisation reasoning (why these specific findings sit in Wave 1 vs. later) is in
[severity-methodology.md](severity-methodology.md). Remediation detail for the three most critical (F-01/F-02, F-03,
F-11/F-12) is in [07-remediation/remediation-advisory.md](../07-remediation/remediation-advisory.md).
