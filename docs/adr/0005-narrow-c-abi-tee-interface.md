# ADR-0005: Define a Narrow Three-Function C ABI as the TEE Module Interface

**Date:** 2026-04-18  
**Status:** Accepted  
**Deciders:** Null and Void

---

## Context

Following ADR-0004, the TEE module is integrated via FFI with a C ABI. The interface between the
TUI and the TEE module must be explicitly defined. The width of this interface directly determines
the trust boundary surface area: every function in the interface is a potential vector for
misuse, unexpected input, or exploitation.

The TEE module has three responsibilities (see ADR-0003):
1. Receive the encrypted license token, verify it, and materialize the signing key inside the
   secure boundary.
2. Sign payloads (prompt hashes + timestamp + device fingerprint) on behalf of the TUI.
3. Securely destroy all key material when the session ends.

The TUI must never receive or handle the raw license key. The interface must enforce this by
design, not by convention.

## Decision

The TEE module interface is defined as exactly **three functions** in a shared C header
(`tee_module.h`), implemented independently by each platform backend:

```c
/**
 * Initialize the TEE module. Verifies the license token, checks device
 * fingerprint binding, and materializes the signing key inside the secure
 * boundary. Returns 0 on success, non-zero error code on failure.
 * On failure, no key material is retained and tee_sign() will always fail.
 */
int tee_init(const uint8_t *license_token, size_t token_len);

/**
 * Sign a payload using the license signing key held in the secure boundary.
 * The payload should be: SHA-256(prompt) || timestamp_u64 || device_fingerprint.
 * Writes the signature to sig_out and its length to sig_len.
 * Returns 0 on success, non-zero on failure (e.g., key not initialized).
 */
int tee_sign(const uint8_t *payload, size_t payload_len,
             uint8_t       *sig_out,  size_t *sig_len);

/**
 * Destroy all key material held in the secure boundary. Must be called
 * before process exit. On TEE-backed platforms, this triggers enclave teardown.
 */
void tee_destroy(void);
```

The TUI links against this header. Platform-specific implementations (Secure Enclave backend,
SGX backend, software hardening backend) all conform to this exact signature.

## Alternatives Considered

- **Richer interface (e.g., expose key derivation, device fingerprinting, token parsing):**
  Each additional function widens the trust boundary. Exposing key derivation to the TUI would
  require the TUI to handle intermediate key material, reintroducing the memory exposure risk
  that the TEE is designed to eliminate.
- **Boolean return from `tee_init` ("license valid: yes/no"):** Classic TOCTOU vulnerability.
  Returning a boolean instead of implicitly holding the key allows an attacker to flip the
  result in memory between the check and the first `tee_sign()` call. The current design
  makes TOCTOU structurally impossible: if `tee_init` fails, `tee_sign` produces no valid
  signature, and the cloud backend rejects all requests regardless of any in-memory state.
- **Expose raw signing key to TUI:** Eliminates the security benefit of the TEE entirely.
  Rejected outright.

## Consequences

- **Security:** The trust boundary surface area is three functions. The TUI never handles raw
  key material. TOCTOU attacks on the license check result are structurally prevented by design.
- **Portability:** All three platform backends (Apple Secure Enclave, Intel SGX, software
  hardening) implement the same header. The TUI is fully decoupled from TEE platform specifics.
- **Testability:** The software hardening backend can be used in CI/CD on any platform without
  requiring TEE hardware. Platform-specific backends are tested on their respective hardware.
- **Auditability:** A security auditor reviewing the TUI-TEE boundary needs to inspect exactly
  three call sites in the TUI source code.
