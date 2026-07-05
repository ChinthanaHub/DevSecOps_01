# Architecture Narrative — HLD & LLD — Module 11/12

This narrative explains the security decisions behind [hld-diagram.drawio](hld-diagram.drawio) and
[lld-diagram.drawio](lld-diagram.drawio) (preview renders: [hld-preview.html](hld-preview.html),
[lld-preview.html](lld-preview.html)), and — per the assessment's Section 8 note — at least one alternative design
considered and rejected for each diagram, with the reasoning why. Nothing here repeats what Modules 1–10 already argue
in depth; it explains how those decisions actually landed on the page.

## 1. HLD — key security decisions

**Trust boundaries are drawn around governance responsibility, not around network diagram convenience.** The five
dashed boundaries — CI/CD, Identity & Access Governance, and one per cloud landing zone, plus centralised
Observability — each represent a place where a *different party or control* takes over responsibility for what
crosses into it. That's deliberate: a reader should be able to ask "who is accountable for what happens inside this
box" and get a single answer per boundary, which a box-placement-only diagram doesn't guarantee.

**No static credential crosses a trust boundary anywhere on the diagram.** Every arrow from the Identity boundary into
a landing zone is drawn dashed and labelled with a short-lived token, never a stored secret — this is the one visual
rule that ties directly back to Module 3's federation decision and to the F-11/F-12/F-18 findings it closes.

**The same four-tier segmentation model (Edge/Application/Data/Management) is drawn identically in all three landing
zones**, with only the native construct changing (Security Groups vs. NSGs vs. VPC firewall rules) — this is Module
4's point made visually: three providers, one philosophy, not three.

**Key management is drawn per-cloud, not centralised** — each landing zone has its own KMS/Key Vault box rather than
one shared key-management box feeding all three. This is the most visually counter-intuitive choice on the diagram
(a single shared box would look "simpler"), so it's called out explicitly below as a rejected alternative.

**Observability is centralised, but drawn as receiving from all three zones rather than sitting inside any one of
them** — reflecting that detection must survive a compromise of any single landing zone.

### Alternative considered and rejected — centralised cross-cloud KMS/HSM

**What it would have looked like:** one external HSM/KMS box, positioned centrally, with all three landing zones'
Data tiers pointing into it for encrypt/decrypt — visually simpler than three separate KMS boxes, and a single audit
trail to draw.

**Why rejected:** a single compromised master key would affect every provider's encrypted data simultaneously, not
just one cloud's — the wrong trade for a government estate where blast-radius containment is the stated priority
(Module 5, decision table). It would also have created a jurisdiction problem if that central key store sat in the
wrong region relative to a workload's data-residency obligation, and it requires custom integration work per provider
that adds latency to every encrypt/decrypt call — a multi-quarter build the compliance deadline doesn't allow.
Per-cloud-native KMS, unified by one key-management *policy* rather than one key *store*, was chosen instead — it's
why the HLD shows three KMS boxes, not one.

### Alternative considered and rejected — direct cross-cloud VPC/VNet peering mesh

**What it would have looked like:** direct network peering (or equivalent) between the AWS, Azure, and GCP landing
zones, so a workload on any provider could reach a workload on any other provider directly — the more "connected"
looking diagram, and arguably closer to what a naive reading of "multi-cloud estate" suggests.

**Why rejected:** every direct peer is a new segmentation boundary that has to be individually reasoned about, and a
full mesh across three providers multiplies that reasoning burden as more workloads and providers onboard rather than
keeping it constant. In practice, the only genuinely required cross-cloud traffic identified in this review is a
shared logging destination (Module 6) — a single, explicitly-provisioned, individually-reviewed interconnect covers
that need without opening a default cross-cloud network path. This is why the HLD carries an explicit callout —
"No direct AWS ↔ Azure ↔ GCP network path by default" — rather than drawing any inter-zone network lines at all.

## 2. LLD — key security decisions

**The workload chosen is `web-app-db`** — the same EC2-app-to-RDS workload used in the Module 9 threat model, not a
new example. Reusing it means a panel following this submission end-to-end sees one workload go from findings
(Module 1) → threat model (Module 9) → target-state LLD (Module 12), rather than three unconnected illustrations.
It's also the richest single workload in the reference repo, tied to the largest finding cluster (F-03, F-11–F-15,
F-19, F-21, F-25).

**There is no SSH/RDP path to any instance, anywhere on the diagram.** Administrative access, if ever required, is
via AWS Systems Manager Session Manager only — no listening inbound management port exists at all. This is a
stronger fix than "restrict port 22 to a narrow CIDR"; it removes the finding class (F-14) rather than shrinking it.

**IMDSv2 is enforced (`http_tokens = "required"`) on the app instance**, closing the specific credential-theft pivot
the Module 9 threat model identified (T7: an SSRF bug reaching instance metadata to steal the role's temporary
credentials).

**Two IAM roles replace the two wildcard grants, each scoped to what its component actually does** — not one
role that both the pipeline and the running application share. `aws_iam_role.ci_pipeline` (Module 3, F-11/F-18 fix)
is scoped by resource tag to Terraform state access and this-workload-only management actions. A second,
newly-designed `app_instance_role` (extending the same least-privilege model to the runtime instance, which is where
F-12's other wildcard grant actually lived) is scoped to exactly one Secrets Manager ARN — the running application
gets nothing beyond the one credential it needs to read, not account-wide `ec2:*`/`s3:*`/`rds:*`.

**The CI/CD path has zero network route into the VPC.** Provisioning happens over the AWS control-plane API (443/TCP)
using the federated role above — there's no bastion, no VPN, no peering connection from GitLab's runners into the
workload's network at all. The only way infrastructure changes is through the pipeline gates in Module 2, because
there's no other path capable of reaching these resources.

**One workload CMK is shown encrypting four different resource types** (RDS storage, EC2 EBS volumes, the Terraform
state bucket, and the Secrets Manager secret) — making Module 5's "CMK per workload, not per resource" policy
visible as a concrete, traceable design rather than an abstract principle.

**Detection sits in a separate security-tooling/log-archive account**, not inside the workload account. This means an
attacker who fully compromises the workload account still cannot reach, tamper with, or delete the audit trail
describing what they did.

### Alternative considered and rejected — bastion host / SSH jump box for admin access

**What it would have looked like:** a hardened bastion EC2 instance in the public or management subnet, allow-listed
to a small set of source IPs, that administrators SSH into before hopping to the app or database instances — a
familiar pattern, and one many reviewers expect to see on a network diagram like this.

**Why rejected:** it narrows F-14's shape (an open management port reachable too broadly) without eliminating it —
there's still a listening inbound port and a standing network path, just a smaller one. The bastion itself also
becomes a new high-value target requiring its own patching, key rotation, and monitoring lifecycle — a new thing to
secure, not a removal of risk. AWS Systems Manager Session Manager needs no listening inbound port at all,
authenticates through the same IAM identity model as everything else in Module 3, and logs every session to
CloudTrail by default — it closes the finding class instead of shrinking its blast radius, which is why the LLD
states "no SSH/RDP path" as an absolute rather than drawing a bastion with a restricted CIDR.

### Alternative considered and rejected — IAM database authentication instead of a Secrets-Manager-sourced credential

**What it would have looked like:** the application obtains a short-lived (15-minute) IAM-signed auth token to
connect to RDS instead of a password at all, removing the credential-at-rest problem structurally rather than
managing it — this is also the fuller fix the Module 9 threat model names for T3.

**Why rejected for this pass** (not rejected permanently): it requires an application-code change to the PHP
connection driver, which is out of scope for a Terraform/pipeline remediation pass against a hard compliance
deadline, and RDS IAM authentication carries a connection-rate ceiling that hasn't been validated against this
workload's actual traffic pattern. The LLD instead shows a Secrets-Manager-sourced credential with automatic
rotation and least-privilege read access scoped to one ARN — a concrete improvement over the current
plaintext-in-user-data state (F-19) that needs no application code change. This is recorded as the same accepted
residual risk Module 9 already names for T3, with IAM database authentication as the named follow-up engineering
task — not a hypothetical future option, a specific piece of work with a reason it isn't in this pass.

## 3. What isn't re-litigated here

The COTS encryption-gap exception (Module 8) and its residual-risk decision are not re-drawn on either diagram —
that workload is deliberately out of scope for both the HLD (which shows the target-state pattern, not the one
named exception to it) and this LLD's chosen slice (a different workload). Module 8 remains the single place that
decision is made and defended.
