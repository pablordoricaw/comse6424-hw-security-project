# ADR-0005: Define a Narrow Three-Function C ABI as the TEE Module Interface

**Date:** 2026-04-18
**Amended:** 2026-04-19
**Status:** Accepted
**Deciders:** Null and Void

---

## Context

Following ADR-0004, the TEE module is integrated via FFI with a C ABI. The interface between the
TUI and the TEE module must be explicitly defined. The width of this interface directly determines
the trust boundary surface area: every function in the interface is a potential vector for
misuse, unexpected input, or exploitation.

The TEE module has three responsibilities (see ADR-0007):
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
 * The payload should be: SHA-256(nonce || timestamp || license_id).
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

The Go TUI links against this header via `cgo`. Platform-specific implementations
(Apple Secure Enclave backend, Intel SGX backend) both conform to this exact signature.

---

## Platform-Specific Implementation Details

### Apple Silicon: Swift via `@_cdecl`

Go cannot call Swift directly. The bridge is: **Go (cgo) → C header → Swift (`@_cdecl`) → CryptoKit / Secure Enclave**.

Swift exposes C-callable symbols using the `@_cdecl` compiler attribute, which compiles a
Swift function with C calling conventions and exports it under the given C symbol name:

```swift
import CryptoKit
import Foundation

@_cdecl("tee_init")
public func teeInit(
    licenseToken: UnsafePointer<UInt8>?,
    tokenLen: Int
) -> Int32 {
    // Generate or load P-256 Secure Enclave key pair via CryptoKit
    // Verify license token signature
    return 0
}

@_cdecl("tee_sign")
public func teeSign(
    payload: UnsafePointer<UInt8>?,
    payloadLen: Int,
    sigOut: UnsafeMutablePointer<UInt8>?,
    sigLen: UnsafeMutablePointer<Int>?
) -> Int32 {
    // Sign payload using SecureEnclave.P256.Signing.PrivateKey
    // The private key never leaves the Secure Enclave chip
    return 0
}

@_cdecl("tee_destroy")
public func teeDestroy() { }
```

This is compiled into a `.dylib` shared library:

```bash
swiftc -emit-library -module-name TEEModule tee_module.swift -o libteemodule.dylib
```

The resulting `libteemodule.dylib` exports `tee_init`, `tee_sign`, and `tee_destroy` as
standard C symbols. No Objective-C runtime is involved — `@_cdecl` produces pure C ABI
symbols. The Go binary links against this library via `cgo`:

```go
/*
#cgo LDFLAGS: -L${SRCDIR}/lib -lteemodule -rpath @executable_path/lib
#include "tee_module.h"
*/
import "C"
```

**Key security property:** The P-256 signing operation executes inside the Secure Enclave chip.
The Application Processor (where Go runs) only sends the payload in and receives the signature
out. The private key bytes never cross that hardware boundary.

---

### Intel SGX: C/C++ via ECALL

On Intel SGX, the TEE module shim is plain C/C++ using the Intel SGX SDK. No language
bridging is needed — the shim speaks C natively and Go calls it directly via `cgo`.

However, SGX enforces a strict separation between **untrusted code** (outside the enclave,
including the Go App and the C shim) and **trusted code** (inside the enclave). Communication
across this boundary uses **ECALLs** (untrusted → trusted) defined in an EDL file. This is
the "forced IPC by the platform" exception noted in ADR-0004.

```
Go App (cgo)
    │
    ▼
C shim (untrusted, implements tee_module.h)
    │  ECALL: ecall_init() / ecall_sign() / ecall_destroy()
    ▼
SGX Enclave (trusted, holds private key)
    │  sgx_seal_data() / Ed25519 signing
    ▼
Returns via ECALL return value
```

The `tee_init`, `tee_sign`, and `tee_destroy` C ABI functions are implemented in the
**untrusted C shim**, which translates each call into the appropriate ECALL into the enclave.
From the Go App's perspective, the interface is identical to the Apple path — three C functions,
same header, same cgo binding.

**Key security property:** The Ed25519 signing operation executes inside the SGX enclave memory
region, which the untrusted OS cannot read or tamper with. The private key is sealed to the
enclave identity (`MRENCLAVE`) and the platform hardware root, making it unreadable outside
this specific enclave on this specific machine.

---

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
- **Direct Swift-to-Go binding (without C ABI):** No stable Swift ABI exists for cross-module
  FFI outside of Apple's own frameworks. The `@_cdecl` C bridge is the only supported mechanism
  for exposing Swift code to non-Swift callers.

## Consequences

- **Security:** The trust boundary surface area is three functions. The TUI never handles raw
  key material. TOCTOU attacks on the license check result are structurally prevented by design.
- **Portability:** Both platform backends (Apple Secure Enclave via Swift `@_cdecl`, Intel SGX
  via C ECALL shim) implement the same C header. The TUI is fully decoupled from TEE platform
  specifics.
- **Build system:** The Apple backend requires `swiftc` and produces a `.dylib`. The SGX backend
  requires the Intel SGX SDK and produces a `.so`. Each platform's CI runner must have the
  appropriate toolchain. Cross-compilation is not supported for either backend.
- **Testability:** A stub software backend implementing the same C header can be used in CI/CD
  on any platform without requiring TEE hardware.
- **Auditability:** A security auditor reviewing the TUI-TEE boundary needs to inspect exactly
  three call sites in the TUI source code, and two platform-specific implementation files.
