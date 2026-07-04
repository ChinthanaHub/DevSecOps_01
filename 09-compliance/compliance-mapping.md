# Compliance Mapping — Module 10

The programme's actual internal compliance clause text isn't accessible for this exercise, so the domains used below
are **illustrative categories analogous to common, publicly-documented frameworks** (NIST SP 800-53 control
families, ISO/IEC 27001 Annex A, and the UK NCSC Cloud Security Principles, which are the natural reference set for
a government cloud programme) — not a claim about which specific framework or clause number applies. The point of
this module is the **mapping methodology**: given a finding, how do you decide which compliance domain it belongs to,
and what evidence would you actually go collect to demonstrate compliance or justify an exception. That method
transfers directly once the real internal standard is available; the category labels would just be swapped.

## Methodology

For each finding: (1) identify which control domain(s) it touches — often more than one, (2) state what evidence a
compliance reviewer would need to see to consider it closed, and (3) state what evidence would be needed instead to
justify an accepted exception, since not everything closes before go-live.

## Five findings mapped

### F-01/F-02 — Public storage buckets, no public access block

| | |
|---|---|
| **Domain(s)** | Data Protection & Encryption (illustrative: NIST SP 800-53 SC-28/AC-3 family; NCSC Principle 5 — Data in transit/at rest protection); Access Control |
| **Evidence to demonstrate compliance** | `aws s3api get-public-access-block` output for every bucket showing all four settings `true`; a CSPM (Module 6) screenshot/export showing zero open findings for this check class, dated after remediation; the pipeline gate (Module 2) configuration showing this check is hard-fail, as evidence the control is now preventative, not just corrective. |
| **Evidence to justify an exception (if one were needed)** | A documented, time-bound business justification signed by a named owner, plus a compensating control equivalent to Module 8's model — network-layer restriction and enhanced monitoring specifically on that bucket — not just "we'll fix it later" with no interim control. |

### F-03 — Database unencrypted at rest and publicly accessible

| | |
|---|---|
| **Domain(s)** | Data Protection & Encryption (primary); System & Communications Protection (network exposure component) |
| **Evidence to demonstrate compliance** | `aws rds describe-db-instances` showing `StorageEncrypted: true`, `PubliclyAccessible: false`; the KMS key policy showing least-privilege key access scoped to the workload (Module 5); a completed maintenance-window change record showing the snapshot/restore cutover was performed and verified, not just planned. |
| **Evidence to justify an exception** | This is exactly the COTS pattern in Module 8 — vendor confirmation of the technical incompatibility, the compensating controls in place, and the named ITSO-equivalent risk acceptance with a re-review date. A generic "vendor doesn't support it" claim with no vendor documentation would not be sufficient evidence on its own. |

### F-11/F-12 — Wildcard IAM policy on a long-lived credential

| | |
|---|---|
| **Domain(s)** | Access Control / Least Privilege (illustrative: NIST AC-6; NCSC Principle 9 — Identity and authentication); Audit & Accountability (a wildcard policy also weakens the value of audit logs, since almost any action is "authorised") |
| **Evidence to demonstrate compliance** | The IAM policy document itself, showing action/resource scoping and the `aws:ResourceTag` condition (Module 3); `aws iam list-access-keys` confirming no static keys remain for this workload; CloudTrail showing all activity now authenticates via `AssumedRoleWithWebIdentity`, not a long-lived key. |
| **Evidence to justify an exception** | Least-privilege exceptions are the hardest to justify defensibly — an exception here would need a specific, narrow technical blocker (e.g. a legacy tool that genuinely cannot use federated credentials) plus a hard expiry, reviewed on the same cadence as the COTS exception in Module 8. This wasn't required for F-11/F-12 in practice — Module 7's fix closes it directly — but the reasoning here is what would apply if a similar finding elsewhere in the ~100 workloads couldn't be fixed before go-live. |

### F-21 — No centralised audit logging (CloudTrail absent entirely)

| | |
|---|---|
| **Domain(s)** | Audit & Accountability (illustrative: NIST AU-2/AU-6; NCSC Principle 10 — External interface protection & Principle 11/12 audit-adjacent principles) |
| **Evidence to demonstrate compliance** | CloudTrail configuration showing management **and** data events enabled for Restricted-classified resources, delivered to the centralised SIEM destination (Module 6); a log-retention policy document showing retention meets or exceeds the required period; a sample query/alert demonstrating the logs are actually queryable, not just being written to a bucket nobody reads. |
| **Evidence to justify an exception** | Audit logging is one of the few domains where an exception is very hard to justify defensibly — "we chose not to log" has essentially no acceptable business justification for a government programme. This finding is treated as **must-fix**, not exception-eligible, which is itself a decision worth stating explicitly in a compliance mapping rather than leaving implicit. |

### F-14/F-16 — Security groups/NSGs open to the internet on SSH/RDP/HTTP

| | |
|---|---|
| **Domain(s)** | System & Communications Protection (illustrative: NIST SC-7 boundary protection; NCSC Principle 7 — Secure user management / network-adjacent portions of Principle 5) |
| **Evidence to demonstrate compliance** | Security group/NSG rule export showing source restricted to specific ranges/references, not `0.0.0.0/0`/`*`; the network design's segmentation model (Module 4) showing this resource sits in the correct tier; a CSPM scan confirming zero open-management-port findings across the estate, not just this one instance. |
| **Evidence to justify an exception** | A genuinely temporary operational need (e.g. a time-boxed debugging window) with the rule scoped to a specific IP, an automatic expiry (e.g. via a scheduled Terraform destroy or a CSPM auto-remediation), and a named requester — never a standing exception for management-port access from anywhere. |

## Expressing one control across AWS, Azure, and GCP with a single policy-as-code framework

The alternative to the above — maintaining three separate rule sets, one Checkov custom policy per provider, three
different compliance reviewers each interpreting "no public storage" slightly differently — is exactly the drift
this track is meant to prevent. OPA/Conftest (introduced in Module 2) is the mechanism: **one Rego policy, evaluated
against whichever provider's Terraform plan is being reviewed, because the plan JSON structure is normalised by
Terraform itself before OPA ever sees it.**

```rego
package terraform.storage

# One rule, evaluated identically regardless of which provider's resource type triggered it.
deny[msg] {
    resource := input.resource_changes[_]
    is_storage_resource(resource.type)
    not has_public_access_blocked(resource)
    msg := sprintf(
        "%s '%s' does not block public access - Data Protection domain, F-01/F-02 pattern",
        [resource.type, resource.name],
    )
}

is_storage_resource(type) {
    type == "aws_s3_bucket"
}
is_storage_resource(type) {
    type == "azurerm_storage_account"
}
is_storage_resource(type) {
    type == "google_storage_bucket"
}

has_public_access_blocked(resource) {
    resource.type == "aws_s3_bucket"
    resource.change.after.acl != "public-read"
    resource.change.after.acl != "public-read-write"
}
has_public_access_blocked(resource) {
    resource.type == "azurerm_storage_account"
    resource.change.after.public_network_access_enabled == false
}
has_public_access_blocked(resource) {
    resource.type == "google_storage_bucket"
    resource.change.after.uniform_bucket_level_access == true
    # combined with an IAM policy check (not shown) confirming no allUsers/allAuthenticatedUsers binding
}
```

The compliance value of this pattern: a single Rego rule file **is** the evidence artefact — a compliance reviewer
can be shown one policy and told "this is what 'no public storage' means, enforced identically on every provider,"
rather than being shown three Checkov custom-check YAML files and asked to independently verify they say the same
thing. As Azure/GCP onboarding proceeds, new provider-specific `is_storage_resource`/`has_public_access_blocked`
clauses are additive to the same rule, not a parallel rule set — the compliance mapping in this document doesn't
change shape when a new provider is added, only the policy's provider-matching clauses grow.
