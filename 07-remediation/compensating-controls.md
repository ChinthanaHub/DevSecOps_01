# Compensating Controls for a COTS Constraint — Module 8

## The constraint

The financial reconciliation tool's connection driver cannot operate with storage encryption enabled — a
vendor-imposed limitation, confirmed as structural rather than a configuration gap in
[05-data-protection/encryption-key-mgmt.md](../05-data-protection/encryption-key-mgmt.md). It cannot be re-platformed
before the compliance deadline. The data it holds is financial (classification: **Restricted** under Module 5's
model), so this is not a low-stakes exception — it's a Restricted-data workload with no encryption-at-rest, sitting
inside a programme working toward a formal go-live security sign-off.

## At least three compensating controls

Each one draws directly on a design already produced elsewhere in this submission, rather than inventing a new
control in isolation:

1. **Network isolation to the strictest tier the estate has** (from [04-network-zero-trust/network-design.md](../04-network-zero-trust/network-design.md)).
   The tool is placed in its own segment, one step stricter than the standard Data tier: no inbound access except
   from the specific reconciliation application component that needs it, on the specific DB port, and **no egress at
   all** beyond what the database engine itself requires. This doesn't encrypt the data, but it collapses the set of
   paths anything could use to reach it down to one, tightly-controlled route — the absence of encryption matters far
   less if the number of ways to reach the plaintext data is reduced to almost nothing.

2. **Continuous, high-sensitivity detection coverage** (from [06-detection-ir/monitoring-ir-plan.md](../06-detection-ir/monitoring-ir-plan.md)).
   This workload is opted into the **Tier A** alerting posture regardless of its actual production criticality
   ranking, specifically because encryption — the control that would normally provide a silent, passive protection
   layer — isn't available here. Every access to this workload's data path is logged and correlated, and any access
   pattern deviating from the reconciliation tool's own known, narrow usage profile pages on-call immediately, not on
   a delayed review cycle. Detection is doing the job encryption would normally do: making unauthorised access
   expensive and visible, even though it can't make the data unreadable.

3. **Encryption at every layer the vendor limitation does not touch.** The driver limitation is specifically about
   storage-layer encryption at rest; it does not prevent encryption in transit (TLS enforced on every connection to
   the tool, no exception), nor does it prevent encrypting the underlying disk/volume at the infrastructure layer
   *outside* the database engine's own storage encryption feature (e.g. host-level or hypervisor-level volume
   encryption, if the driver's incompatibility is specifically with the database engine's native encryption feature
   rather than with encrypted storage existing at all — this needs vendor confirmation before being relied upon, and
   is listed as an open verification item below, not assumed true).

4. **Compensating access control on the human side.** Standing human access to this workload's underlying data
   store is removed entirely, replacing it with the same just-in-time elevation model from
   [03-identity-governance/cross-cloud-iam-design.md](../03-identity-governance/cross-cloud-iam-design.md), but with
   a shorter time-bound window and mandatory dual-approval (two named approvers, not one) given the absence of an
   encryption backstop.

## Recommended residual risk rating and who accepts it

**Residual risk after compensating controls: High, not Critical.** The original gap (Restricted financial data,
unencrypted at rest) starts Critical under the severity methodology; the compensating controls address exposure and
detection, but do not close the underlying gap — the data remains unencrypted at rest, so the rating cannot be
lowered to Medium in good conscience regardless of how tight the surrounding controls are.

**Who should formally accept it:** this exceeds what a delivery team or even a security review lead can sign off
individually — the risk is time-bound but real, sits on a Restricted-classified financial data workload, and directly
affects the go-live sign-off the whole remediation programme is working toward. This needs the ITSO-equivalent
stakeholder's **named, documented acceptance**, with the compensating controls above listed as the condition of that
acceptance (not an unconditional accept), and a defined re-review date — not accepted once and forgotten.

## Time-bound remediation plan — interim vs. target

| | Interim state (now → go-live) | Target state |
|---|---|---|
| Encryption | None at the storage layer; compensating controls above in place | Vendor-confirmed encrypted-storage-compatible driver, or the tool re-platformed to a version/architecture that supports it |
| Network | Isolated segment, tightest posture in the estate | Same posture retained even after encryption is resolved — isolation was a good idea independent of the encryption gap |
| Ownership | ITSO-equivalent named risk acceptance, reviewed quarterly at minimum | Risk acceptance retired entirely once encryption is resolved |
| Trigger to re-platform | Vendor roadmap review (owner: whoever holds the vendor relationship, not the security review track) at a fixed interval, not "whenever it comes up" | Re-platform scheduled as soon as a compatible driver/version exists, treated as a committed remediation item in the register, not a someday item |

## Preventing this exception from justifying others across the ~100-workload estate

This is the part that's easy to get wrong under deadline pressure — once one Restricted workload has an accepted
encryption exception, the natural failure mode is someone else pointing at it next quarter and saying "we got an
exception for that one, why not this one." Three controls against that specifically:

1. **The exception is tied to the named vendor constraint, not to the workload or the data classification.** It's
   recorded in the findings register as "vendor driver incompatibility, confirmed via [evidence]," not as "Restricted
   financial data workloads may accept unencrypted storage." Any future exception request has to independently prove
   its own structural, vendor-level blocker — citing this one is not, by itself, evidence of anything.
2. **The OPA/Conftest policy gate (Module 2/10) still hard-fails encryption-at-rest for every workload by default,
   including Restricted-classified ones.** This specific workload is the *only* one carrying an explicit,
   individually-reviewed policy exception entry with an expiry date — it is not implemented as a classification-wide
   carve-out, so it can't silently cover a second workload that happens to share the same classification tag.
3. **Every exception request references this one only by its own compensating-control bar, not its outcome.** A new
   request has to show its own equivalent of network isolation + elevated detection + access control tightening — if
   a future team can't produce an equivalent compensating-control set, the precedent argument fails on its own terms,
   regardless of what was accepted here.

**Open verification item:** the vendor's exact incompatibility (native database engine encryption specifically, vs.
any form of encrypted storage) should be confirmed directly with the vendor before compensating control 3 above is
relied upon operationally — this submission treats it as an open question rather than assuming the more favourable
interpretation.
