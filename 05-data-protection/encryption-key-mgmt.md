# Data Protection, Encryption & Key Management — Module 5

## 1. Key management approach: centralised vs. per-cloud-native KMS

**Decision: per-cloud-native KMS (AWS KMS, Azure Key Vault, GCP Cloud KMS), unified by a common key-management
*policy* rather than a single physical key store.**

The trade-off is real and worth stating plainly rather than picking a side by default:

| | Centralised (e.g. one external HSM/KMS fronting all three clouds) | Per-cloud-native KMS |
|---|---|---|
| Operational simplicity | One system to operate, one audit trail | Three systems, three audit trails to correlate |
| Blast radius if a key is compromised | A single compromised master key can affect **every** provider's encrypted data simultaneously | A compromised AWS KMS key affects only AWS-encrypted data; Azure and GCP are unaffected |
| Native integration | Requires custom integration work per provider to plug in an external KMS (external key stores exist but add latency and a new dependency in the encrypt/decrypt path of every read/write) | First-class support for envelope encryption, IAM-integrated key policies, and automatic key rotation with no extra moving parts |
| Fit for this estate | Attractive on paper for "one place to manage everything," but the programme has no current cross-cloud KMS operational capability, and building one is a multi-quarter effort the compliance deadline doesn't allow | Deployable immediately with the identity model from Module 3 already providing the access-control layer |

Per-cloud-native KMS wins here specifically because of the **blast radius** column: for a government programme,
"one compromised key affects one cloud's data, not the whole estate" is a stronger security property than
operational convenience, and it's also the more realistic amount of work to actually deliver against the compliance
deadline. The unifying layer is policy, not infrastructure: every workload's key policy follows the same rules
(least-privilege key access scoped by workload tag — same tag model as Module 3's IAM redesign — mandatory rotation,
no key ever directly accessible to application code, only via each provider's envelope-encryption SDK).

This directly fixes F-07 (`aws_db_instance.default` has no KMS key referenced at all) and generalises the pattern
already done correctly once in this repo (`aws_s3_bucket.logs` correctly uses a customer-managed KMS key — F-10 is
literally that same pattern missing on the sibling `financials` bucket that holds more sensitive data).

## 2. Is BYOK/HYOK warranted anywhere in this estate?

Not universally — most of the ~100 workloads are well served by provider-managed CMKs (customer-managed, but
provider-hosted). BYOK (bringing externally-generated key material into the provider's KMS) or HYOK (key material
that never leaves external/on-prem custody) is warranted only where:

- Data classification (below) is **Restricted**, and
- There is a specific regulatory or contractual requirement that key material must never be derivable or held by
  the cloud provider, even in escrowed form.

Given the government programme context, this most plausibly applies to whichever workloads hold data under the
strictest data-residency/sovereignty obligations (see below) — not as a blanket policy, because HYOK adds real
operational fragility (key availability now depends on an external HSM's uptime for every decrypt operation) that
isn't justified for the majority of the estate's storage- and database-backed web apps.

## 3. Data classification approach

Not every workload gets the same controls — that's the point of tiering, and it plugs directly into the network
tiering from Module 4 and the policy gate from Module 2:

| Classification | Examples in this estate | Controls |
|---|---|---|
| **Public** | Static web assets, public documentation | Encryption at rest still mandatory (defence-in-depth, cheap to apply universally), no additional key restriction |
| **Internal** | Internal tooling data, non-customer operational data | CMK per workload, standard rotation, access scoped by workload tag |
| **Restricted** | Customer data, financial data (`aws_s3_bucket.financials`, database resources), credentials | CMK per workload, **mandatory** key-use logging (every encrypt/decrypt call auditable — feeds Module 6), BYOK/HYOK evaluated case-by-case, and this is the tag the OPA/Conftest policy in Module 2 checks against before allowing a resource to skip an encryption gate |

Classification is applied as a resource tag at the Terraform module level, so it's declared once, enforced by the
pipeline, and visible to both the network design (which tier a workload sits in) and the key management design
(which key policy applies) without maintaining two separate mappings.

## 4. Data residency / sovereignty (conceptual)

For a government programme, this is a design input, not an afterthought once workloads exist:

- Every provider's regions used must be within the jurisdiction the programme is bound to operate in — this is
  enforced as a policy check (region allow-list per provider) at the same OPA/Conftest gate as everything else, so a
  workload can't be stood up in a non-compliant region by omission.
- Key material for **Restricted**-classified data should not leave the same jurisdiction as the data it protects —
  relevant when evaluating cross-cloud DR (Module 13) and the earlier centralised-vs-per-cloud KMS decision: a
  centralised external KMS in the wrong jurisdiction would have created a sovereignty problem for every workload
  simultaneously, which is a second, independent reason per-cloud-native KMS was chosen over centralising.
- Support/administrative access to encrypted data (cloud provider support access, break-glass per Module 3) should be
  contractually and technically restricted to personnel/jurisdictions consistent with the programme's sovereignty
  requirements — flagged here as a procurement/contractual control, not something Terraform can enforce, but
  something the compliance mapping (Module 10) needs an evidence source for.

## 5. Addressing the COTS encryption gap directly

The financial reconciliation tool's connection driver cannot operate with storage encryption enabled — the vendor
limitation is real, not a configuration oversight, so the answer isn't "turn encryption on anyway." This data
classification model still applies: the tool's data is **Restricted**, so it *should* have full at-rest encryption
under this design, and doesn't. That gap is not solved in this module — it's solved at the network and detection
layers instead, because encryption is the wrong tool for a workload that structurally cannot use it. The specific
compensating controls (drawing directly on the Data-tier network isolation from Module 4 and the detection design
from Module 6) and the residual risk decision are in
[07-remediation/compensating-controls.md](../07-remediation/compensating-controls.md) — this module defines *why*
the gap can't be closed with more encryption engineering; Module 8 defines what stands in its place.
