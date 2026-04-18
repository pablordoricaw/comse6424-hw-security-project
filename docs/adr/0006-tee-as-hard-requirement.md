# ADR-0006: Require TEE Hardware as Minimum System Requirement

**Date:** 2026-04-18  
**Status:** Accepted  
**Supersedes:** [ADR-0003](0003-tee-as-additive-enhancement.md)  
**Deciders:** Null and Void

---

## Context

ADR-0003 established a layered, gracefully degrading architecture where software portable hardening
(white-box cryptography, CFI, constant-time implementations) served as a universal baseline, with
TEE integration as an additive enhancement on Apple Silicon and Intel SGX platforms.

Upon further analysis, the software hardening fallback path presents two problems that outweigh
its portability benefit:

1. **It is the weakest link and the most attractive attack target.** A sophisticated attacker
   who cannot break the TEE-backed path will look for ways to make the system believe TEE is
   unavailable, forcing execution into the software-only fallback. The existence of a weaker
   fallback path increases the overall attack surface of the system.

2. **It makes hardware fingerprinting fundamentally weaker.** On non-TEE platforms, every
   hardware attribute visible to userspace (MAC address, CPU ID, RAM size, storage serial)
   is spoofable via software, a VM, or kernel-level access. There is no non-spoofable hardware
   anchor available, making device binding a best-effort rather than a cryptographic guarantee.
   This residual risk is significant enough that it undermines the license enforcement goal.

Additionally, scoping to Apple Silicon and Intel SGX still satisfies the project's portability
requirement: these represent two genuinely distinct hardware architectures (ARM and x86) and
microarchitectures, and together cover the dominant developer laptop market.

Intel TDX (Trust Domain Extensions), the forward-looking successor to SGX, is focused on
protecting cloud virtual machines from a malicious hypervisor rather than protecting individual
user-space applications. There is no announced Intel successor to SGX for the desktop application
use case, meaning SGX's supported hardware population will shrink over time as older machines
age out.

## Decision

CloseCode will require **Apple Silicon (Secure Enclave) or Intel SGX** as a minimum hardware
requirement. The software hardening fallback path from ADR-0003 is eliminated.

At install time, CloseCode detects the available TEE platform:

```
System requirement check at install time
        │
        ├─► Apple Silicon detected  →  Secure Enclave backend (ARM)
        │
        ├─► Intel + SGX detected    →  SGX enclave backend (x86)
        │
        └─► Neither detected        →  Installation aborted:
                                       "CloseCode requires Apple Silicon or Intel SGX.
                                        Your hardware is not supported."
```

Software hardening techniques (CFI, constant-time crypto, LFENCE barriers, Rowhammer mitigations)
are retained as **defense-in-depth layers within each TEE-backed path**, not as a standalone
fallback. They protect the Normal World code paths that exist outside the TEE boundary.

## Alternatives Considered

- **Retain the software hardening fallback (ADR-0003):** Broader hardware support but introduces
  a structurally weaker code path that an attacker can force the system into. The hardware
  fingerprinting design is also significantly weaker without a TEE anchor. Rejected in favor of
  a cleaner, stronger security posture.
- **Support AMD via software hardening only:** AMD has no suitable user-space TEE for this use
  case (AMD PSP/SEV is designed for VM isolation, not application-level trusted execution).
  Supporting AMD would require the software fallback, which is rejected above.
- **Wait for a future AMD user-space TEE:** No announced roadmap for such a feature. Not a
  practical option for this project.

## Consequences

- **Security:** Eliminates the weakest code path. Every supported execution environment has a
  hardware-anchored, non-spoofable device identity via TEE attestation. The attack surface is
  reduced to the two well-defined TEE integration paths.
- **Hardware fingerprinting:** TEE attestation becomes the sole and sufficient device identity
  proof. The weighted fuzzy fingerprint fallback design is no longer needed (see ADR-0007).
- **Portability:** CloseCode supports two distinct architectures (ARM via Apple Silicon, x86 via
  Intel SGX) and satisfies the project's cross-architecture portability requirement.
- **Market scope:** AMD desktop/laptop users and non-SGX Intel Core laptop users (11th gen+
  consumer SKUs) cannot run CloseCode. This is a known limitation, accepted in exchange for
  a cleaner security design. Documented as a deployment constraint, not a residual risk.
- **Longevity:** As SGX-capable Intel hardware ages out of the market and Apple Silicon becomes
  increasingly dominant, the SGX backend may eventually be deprecated. The architecture supports
  this gracefully — removing the SGX backend does not affect the Secure Enclave path.
- **Complexity:** Two TEE codepaths are maintained (down from three considered in ADR-0003).
  No software fallback path to maintain or audit.
