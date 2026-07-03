# Network Security & Zero-Trust Architecture — Module 4

## Framing

F-14 (AWS security group open on 22/80 to `0.0.0.0/0`) and F-16 (Azure NSG `bad_sg` open on 22/3389 to `*`) are the
same misconfiguration in two different providers' syntax. That's the tell that network security here can't be
"AWS security groups done well" plus "Azure NSGs done well" as separate exercises — it needs one segmentation and
trust model, expressed natively per provider.

## 1. Segmentation strategy

Segmentation is by **workload sensitivity tier**, not by cloud provider or account boundary alone — the tier drives
the policy, the account/subscription/project boundary is just where that policy is enforced today.

| Tier | Examples in the estate | Segmentation rule |
|---|---|---|
| **Edge** | Public-facing web front ends, the handful of serverless components with public endpoints | Only tier permitted a public listener at all. Everything inbound terminates at a WAF/API gateway equivalent before reaching compute. |
| **Application** | App servers, legacy VM-hosted applications (e.g. `aws_instance.web_host`, `db_app`) | No public IP (closes F-14 directly — port 80/22 should never have been reachable from `0.0.0.0/0` in the first place, because this tier has no public listener by design, not because a rule was tightened after the fact). Inbound only from the Edge tier's security group/NSG, on the specific app port. |
| **Data** | Databases (`aws_db_instance.default`, Azure SQL, `google_sql_database_instance.master_instance`), storage | No public IP, no public endpoint. Inbound only from the Application tier, on the DB port only (closes the pattern behind F-03/F-04/F-05). Egress restricted to nothing but the DB engine's own replication/backup traffic — closes F-15's unrestricted `0.0.0.0/0` egress on the RDS security group. |
| **Management/CI** | GitLab runners, break-glass access paths | No inbound from Edge or Application tiers at all — this is a separate plane. Reachable only from the identity-governed paths in Module 3. |

Cross-provider enforcement is the same rule, different native construct: AWS Security Groups (tier-to-tier
references, not CIDR ranges), Azure NSGs + Application Security Groups (same referential model), GCP VPC firewall
rules with service-account- or tag-based targets. **The rule "Data tier accepts inbound only from Application tier,
by identity/tag reference, never by broad CIDR" is written once as a design principle and implemented three times.**

## 2. Cross-cloud connectivity

Government landing zones already separate account/subscription/project per environment; multi-cloud connectivity
needs to extend that boundary, not flatten it.

- **Within a provider:** hub-and-spoke via each provider's native transit primitive — AWS Transit Gateway, Azure
  Virtual WAN/vNet peering through a hub, GCP Network Connectivity Center. Spokes (workload VPCs/VNets) never peer
  directly with each other; everything routes through the hub so segmentation policy is enforced in one place.
- **Cross-provider (once Azure/GCP onboard):** no direct AWS-to-Azure or AWS-to-GCP network path is established
  by default. Cross-cloud traffic that's genuinely required (e.g. a shared logging destination, see Module 6) goes
  through a small number of explicitly-provisioned private interconnects (e.g. a dedicated VPN or partner
  interconnect between hubs), each one justified and reviewed individually — cross-cloud connectivity is the
  exception, not the default topology, because every cross-cloud link is a segmentation boundary that has to be
  separately reasoned about.
- **Public internet exposure:** only the Edge tier's WAF/API gateway layer has a public IP/listener, on every
  provider. Everything else — including every resource behind F-01 through F-06 — should have no public exposure
  path at the network layer at all, independent of whatever the storage/database-level access control is set to.
  This is deliberate defence-in-depth: F-03's database was both `publicly_accessible = true` *and* reachable at the
  network layer. Fixing only one of those layers would still have left an exposure path.

## 3. Egress control

Default posture is **egress-denied**, allow-listed per workload:

- Application tier: egress permitted only to the specific Data tier resources it depends on, the package/module
  registry needed at deploy time (scoped to that registry's endpoints, not `0.0.0.0/0`), and the observability
  pipeline (Module 6).
- Data tier: no general internet egress at all. The only egress a database resource should ever need is
  provider-managed backup/replication traffic, which stays on the provider's private network path.
- This directly closes F-15 (unrestricted egress on the RDS security group) — under this model that rule shouldn't
  exist; egress is scoped to nothing further than the subnet's NAT/private endpoint path.
- Enforced with AWS VPC endpoint policies + restrictive NAT/egress-only routing, Azure NSG outbound rules + Azure
  Firewall for centralised egress filtering, and GCP egress firewall rules + Cloud NAT — again, one rule, three
  native mechanisms.

## 4. Avoiding three separate network philosophies as Azure/GCP onboard

The risk isn't that Azure and GCP use different constructs — that's unavoidable — it's that without a shared model,
three different network engineers make three different judgment calls about what "reasonably segmented" means. This
design avoids that by keeping the **tiering model and the hub-and-spoke topology identical across providers**, and
letting only the enforcement primitive vary:

- The same four sensitivity tiers apply regardless of provider — there's no "Azure has five tiers because Azure
  makes that easier" drift.
- The policy-as-code layer from Module 2/10 (OPA/Conftest) expresses "Data tier resources must have no public IP and
  inbound restricted to Application tier" as one policy evaluated against Terraform plans from any provider, so the
  rule can't silently diverge between an AWS PR and an Azure PR reviewed by different people.
- Network architecture review for a new Azure/GCP workload asks "which tier is this and does its config match that
  tier's rule," not "what does good Azure networking look like" as a fresh question each time.

This segmentation model is one of the three pillars (identity, network, data protection) that the final presentation
(Section 6) is expected to narrate as one connected story — see how a Data-tier resource here is also the resource
that gets the encryption treatment in
[05-data-protection/encryption-key-mgmt.md](../05-data-protection/encryption-key-mgmt.md).
