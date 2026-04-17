# Mitigation Traceability Matrix

**Project:** CloseCode — Software License Server Immune to Software and Microarchitectural Attacks  
**Team:** Null and Void  
**Status:** Draft  
**Last Updated:** 2026-04-16

> This document maps every identified threat from `THREAT_MODEL.md` to a specific mitigation,
> the ADR that justifies the design decision, and the source code location where it is implemented.
> A threat without a row in this table is an unmitigated risk that must appear in the Residual Risk section.

---

## Traceability Matrix

| # | Threat (from THREAT_MODEL.md) | Mitigation Technique | ADR Reference | Code Reference | Status |
| :- | :--- | :--- | :--- | :--- | :--- |
| 1 | Binary patching to skip license check | Encrypt application binary at rest; decrypt only with valid license key | TODO | TODO | 🔴 Not Started |
| 2 | Memory dump to extract signing key | Zero-out key material immediately after use; use `mlock` + `madvise(MADV_DONTDUMP)` | TODO | TODO | 🔴 Not Started |
| 3 | TOCTOU flip of license validity flag | Entangle license key with execution: key *is* the decryption key for the binary | TODO | TODO | 🔴 Not Started |
| 4 | Control flow hijack bypassing `check_license()` | Software CFI via compiler instrumentation (LLVM CFI or `-fsanitize=cfi`) | TODO | TODO | 🔴 Not Started |
| 5 | License token replay on unlicensed machine | Hardware fingerprint bound into license token (MAC address + CPU serial) | TODO | TODO | 🔴 Not Started |
| 6 | MITM on license server response | TLS with certificate pinning on client | TODO | TODO | 🔴 Not Started |
| 7 | Spectre V1 leaking license key | `lfence` barriers after bounds checks; constant-time comparison for license validation | TODO | TODO | 🔴 Not Started |
| 8 | Flush+Reload recovering signing key | Disable shared memory mappings for key material; use dedicated memory region | TODO | TODO | 🔴 Not Started |
| 9 | Rowhammer bit flip on license check result | Guard pages around license check data structures; double-checked locking with redundant copies | TODO | TODO | 🔴 Not Started |
| 10 | MDS/RIDL leakage across hyperthreads | `VERW` instruction flush before context switch; disable HT if performance allows | TODO | TODO | 🔴 Not Started |

---

## Status Legend

| Symbol | Meaning |
| :--- | :--- |
| 🔴 Not Started | Threat identified, no mitigation implemented yet |
| 🟡 In Progress | Mitigation partially implemented or under review |
| 🟢 Implemented | Mitigation fully implemented and referenced in code |
| ⚪ Accepted Risk | Explicitly accepted as residual risk with justification in THREAT_MODEL.md |
