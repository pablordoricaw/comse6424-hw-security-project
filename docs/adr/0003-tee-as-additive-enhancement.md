# ADR-0003: TEE as Additive Security Enhancement with Software Hardening as Baseline

**Date:** 2026-04-18  
**Status:** Superseded by [ADR-0006](0006-tee-as-hard-requirement.md)  
**Deciders:** Null and Void

---

## Context

The project requirement states that CloseCode should ideally be portable across architectures and
microarchitectures. Trusted Execution Environments (TEEs) provide the strongest available protection
for license key material and the license check integrity — they physically prevent a root-level
attacker from reading key material out of memory and make Rowhammer attacks against key material
non-viable.

However, the three primary TEE platforms available on developer laptops speak entirely different
programming models and APIs:

- **Apple Secure Enclave** — available on all Apple Silicon Macs; uses CryptoKit/Secure Enclave API (Swift/Objective-C)
- **Intel SGX** — available only on Intel Xeon and select vPro enterprise SKUs; deprecated on all
  consumer/mainstream Intel Core processors since 11th generation
- **AMD Secure Processor (PSP/SEV)** — designed for VM isolation in cloud environments, not for
  user-space trusted application execution; no equivalent of an SGX enclave for desktop applications

Relying solely on TEEs would make the design non-portable: AMD desktop machines have no suitable
TEE for this use case, and a significant portion of Intel laptops no longer have SGX. A pure
TEE-only design would either exclude large portions of the developer market or require shipping
a non-hardened fallback with no documented security guarantees.

Software-only portable hardening techniques (white-box cryptography, software CFI, constant-time
implementations, Rowhammer guard pages, LFENCE barriers) run on every platform regardless of TEE
availability but provide weaker guarantees — a root-level attacker with sufficient capability can
still extract keys from normal process memory.

## Decision

We will implement a **layered, gracefully degrading architecture**:

1. **Baseline (all platforms):** Software portable hardening — white-box cryptography, software CFI,
   constant-time license validation, Rowhammer guard pages, and LFENCE/MFENCE barriers around
   speculative execution boundaries. This layer runs on every platform unconditionally.

2. **Enhancement (Apple Silicon):** Apple Secure Enclave integration for hardware-bound key storage
   and signing. The license key never enters normal process memory on this platform.

3. **Enhancement (Intel with SGX):** Intel SGX enclave integration for license check and key storage.
   Scoped to Xeon and vPro enterprise SKUs where SGX is available.

4. **Residual risk documentation:** On platforms without TEE support (AMD, non-SGX Intel, Linux on
   ARM), the software hardening baseline applies and residual risks are explicitly documented in
   `THREAT_MODEL.md`.

The TEE is an **additive security enhancement**, not the primary defense boundary. The software
hardening layer is the portable baseline that satisfies the portability requirement.

## Alternatives Considered

- **TEE-only design:** Strongest security on supported platforms but excludes AMD desktop machines
  entirely and a growing majority of Intel laptops. Does not satisfy the portability requirement.
- **Software-only design:** Fully portable but provides weaker guarantees against a root-level
  attacker with memory access. Does not leverage available hardware security features.
- **Require TEE as minimum hardware:** Would artificially restrict the user base and is inconsistent
  with the project's portability goal.

## Consequences

- **Security:** On Apple Silicon and SGX platforms, key material never enters normal process memory.
  On other platforms, software hardening provides meaningful but weaker protection — this residual
  risk is explicitly accepted and documented.
- **Portability:** CloseCode runs and enforces the license on all target platforms.
- **Complexity:** Two TEE integration codepaths must be maintained (Apple Secure Enclave and Intel SGX).
  AMD has no suitable equivalent and is intentionally excluded from TEE enhancement.
- **Honesty:** The graceful degradation model allows the team to rigorously document residual risk
  per platform, directly satisfying the project rubric's evaluation requirement.

---

> **Note:** This decision was superseded by [ADR-0006](0006-tee-as-hard-requirement.md), which
> eliminates the software hardening fallback path and requires TEE hardware as a minimum system
> requirement. The rationale is that the fallback path was the weakest link in the design and
> its elimination simplifies the architecture, reduces attack surface, and enables a cleaner
> hardware fingerprinting design based solely on TEE attestation.
