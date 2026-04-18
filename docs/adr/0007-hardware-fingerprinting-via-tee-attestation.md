# ADR-0007: Hardware Fingerprinting via TEE Attestation and Challenge-Response Verification

**Date:** 2026-04-18  
**Status:** Accepted  
**Deciders:** Null and Void

---

## Context

CloseCode must bind a license to a specific device so that a valid license token cannot be copied
and used on an unlicensed machine. ADR-0006 established that CloseCode requires either Apple
Silicon (Secure Enclave) or Intel SGX as a minimum hardware requirement, eliminating the need
for a software-based fuzzy fingerprint fallback.

With TEE hardware guaranteed to be present on all supported platforms, the device identity
problem changes fundamentally:

- **Every hardware attribute visible to userspace is spoofable** (MAC address, CPU ID, RAM size,
  storage serial) via software, a VM, or kernel-level access. A fingerprint built from these
  attributes is a best-effort measure, not a cryptographic guarantee.
- **A TEE-generated key pair is non-spoofable by construction.** The TEE generates the private
  key internally and the hardware guarantees it never leaves the secure boundary. No userspace
  process, kernel exploit, or memory scraping attack can extract it.
- **TEE attestation provides a verifiable proof of genuine hardware.** Apple's Secure Enclave
  and Intel SGX both produce attestation certificates rooted in hardware manufacturer CAs,
  allowing the server to verify that a key pair was genuinely generated inside real TEE hardware
  and not fabricated by an attacker.

As a result, hardware fingerprinting based on collected device attributes (the approach considered
before ADR-0006) is replaced entirely by a TEE key pair and challenge-response protocol.

## Decision

### Device Identity: TEE-Generated Key Pair

Device identity is established by a **key pair generated inside the TEE at first activation**.
The private key is hardware-bound and non-exportable. The public key serves as the device
identifier stored on the license server.

- **Apple Silicon:** The Secure Enclave generates a P-256 (ECDSA) key pair flagged as
  non-exportable and bound to the Secure Enclave's hardware UID. The key survives OS reinstalls
  but is destroyed if the Secure Enclave is wiped (e.g., Erase All Content and Settings).
- **Intel SGX:** The enclave generates an Ed25519 key pair using the SGX sealing key derived
  from `MRENCLAVE` and the platform's hardware root. The key is sealed to the enclave and
  platform; reinstalling CloseCode requires re-activation.

### First Activation Protocol

```
1. User purchases license → server issues license_id
2. CloseCode installed → TEE generates device key pair
   (private key never leaves TEE boundary)
3. TEE produces platform attestation:
   - Apple: DeviceCheck / App Attest certificate chain rooted in Apple CA
   - Intel: SGX quote signed by Intel Attestation Service (IAS) or DCAP
4. Client sends to license server:
   (license_id, device_public_key, platform_attestation)
5. Server verifies attestation against Apple/Intel root CA
6. Server stores: license_id → device_public_key
   (stored as HMAC(server_secret, device_public_key) — never in plaintext)
7. Activation complete; license is now device-bound
```

### Per-Launch Verification Protocol (Challenge-Response)

Verification at every launch uses a **challenge-response protocol** based on digital signatures.
The TEE signs a fresh server-issued nonce with the device private key. The server verifies the
signature with the stored public key. No hardware attributes are transmitted or recomputed.

```
1. Client connects to license server, sends license_id
2. Server generates a cryptographically random nonce (32 bytes), stores it with a short TTL
3. Client passes nonce to TEE
4. TEE computes: σ = Sign(private_key, SHA-256(nonce || timestamp || license_id))
5. Client sends (σ, timestamp, license_id) to server
6. Server verifies:
   a. Nonce exists and has not expired (prevents replay)
   b. Timestamp is within acceptable skew (±60 seconds)
   c. Verify(device_public_key, σ, SHA-256(nonce || timestamp || license_id)) == true
7. If valid: server issues a short-lived session token (TTL: 1 hour)
8. Client uses session token to authenticate requests to the cloud LLM backend
9. On session token expiry: client repeats from step 1
```

### Why Signing, Not Encryption

The goal is to prove **authenticity** (that this specific TEE was present and active), not
confidentiality. Digital signatures achieve this: only the private key holder can produce a
valid signature over a fresh nonce, and the public key is sufficient to verify it. No secret
material crosses the network at any point.

### Connection to ADR-0005 (Narrow C ABI Interface)

The `tee_init()` / `tee_sign()` / `tee_destroy()` interface defined in ADR-0005 directly
supports this protocol:
- `tee_init()` performs TEE key generation (first activation) or key loading (subsequent launches)
  and verifies the license token binding
- `tee_sign()` implements step 4 of the per-launch verification: signs the challenge payload
- `tee_destroy()` zeroes any in-memory state and tears down the enclave session

## Alternatives Considered

- **Weighted fuzzy fingerprint of hardware attributes:** Required before ADR-0006 scoped
  CloseCode to TEE-only platforms. Every component attribute is spoofable; the design relies
  on raising the cost of spoofing rather than making it cryptographically impossible. Eliminated
  by the TEE hard requirement in ADR-0006.
- **OS keychain installation secret:** Binds to OS installation rather than hardware. Survives
  a NIC swap but is lost on OS reinstall and extractable by an attacker with admin access and
  the user's credentials. Weaker than TEE attestation and unnecessary given ADR-0006.
- **Send hardware attributes alongside TEE attestation for belt-and-suspenders:** Adds
  complexity without meaningful security improvement — the TEE attestation already provides
  a non-spoofable hardware anchor. Additional attributes would only add surface area for
  unsafe parsing.

## Consequences

- **Security:** Device identity is cryptographically non-spoofable on all supported platforms.
  Replay attacks are prevented by single-use nonces. MITM attacks are prevented by TLS on the
  license server channel (see ADR-0002) and by the signature binding the nonce to this specific
  device key. The server stores only a public key — a database breach exposes no exploitable secrets.
- **User experience:** First activation requires a one-time internet connection. Subsequent
  launches require a license server round-trip only at startup (session token covers the rest
  of the session). If the user wipes their Secure Enclave or reinstalls on a new machine,
  re-activation is required — this is expected behavior for node-locked licensing.
- **Portability:** The `tee_sign()` ABI is identical across Apple Secure Enclave and Intel SGX
  backends. The license server verification logic is platform-agnostic.
- **Server complexity:** The license server must implement nonce generation, TTL management,
  and platform-specific attestation verification (Apple CA and Intel IAS/DCAP). This is
  non-trivial but well-documented by both vendors.
