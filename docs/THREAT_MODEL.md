# Threat Model

**Project:** CloseCode — Software License Server Immune to Software and Microarchitectural Attacks  
**Team:** Null and Void  
**Status:** Draft  
**Last Updated:** 2026-04-20

---

## 1. System Overview

CloseCode is a node-locked, always-online AI coding agent that enforces license validity before
allowing access to a cloud-hosted LLM backend. The system is designed so that a valid license is
bound to a specific device through a TEE-generated key pair and platform attestation, rather than
through spoofable hardware attributes or locally cached license state.

The architecture has three primary containers:

- **CloseCode App** — local TUI application running on the client machine. It collects the user's
  prompt, enriches it with local AST and RAG context, requests TEE signatures via the License
  Manager, and sends authenticated requests to the AI Proxy.
- **License Server** — cloud service that performs activation-time TEE attestation verification,
  binds a license to a device public key, and issues short-lived signed session tokens after
  per-launch challenge-response verification.
- **AI Proxy** — thin authenticated forwarding layer that validates session tokens, strips them,
  injects the AI provider API key, and relays requests to the external AI Model API.

CloseCode requires **Apple Silicon (Secure Enclave)** or **Intel SGX** as a minimum hardware
requirement. Systems without a supported TEE cannot install or run the software.

The security goal is **license enforcement against a root-capable attacker on the client machine**,
including attackers capable of process memory inspection, binary patching, replay attacks, and
selected microarchitectural attacks. The system is not intended to protect against compromise of
vendor TEE firmware, the cloud provider, or the license server operator.

---

## 2. Architecture and Trust Boundaries

### Trust Boundary Summary

| Component | Trust Level | Notes |
| :--- | :--- | :--- |
| CloseCode App code outside TEE | Untrusted | Runs on an attacker-controlled client OS; subject to debugging, patching, and memory inspection |
| TEE Module + Secure Enclave / SGX enclave | Conditionally trusted | Trusted only to the extent that vendor TEE guarantees hold; private key is intended to remain non-exportable |
| Client OS and kernel | Untrusted | Attacker is assumed to have root/administrator access |
| Client RAM outside TEE | Untrusted | Subject to memory scraping, Rowhammer-style corruption, and side-channel observation |
| License Server | Trusted | Operated by the developer; validates attestation and issues signed session tokens |
| License Store | Trusted | Stores only HMAC(server_secret, device_public_key) and license status, never raw private keys |
| AI Proxy | Trusted | Enforces token validation before forwarding and holds the live AI provider API key in process memory |
| AI Model API | Trusted | Third-party LLM provider; receives only requests forwarded through the AI Proxy |
| Network channel (App ↔ License Server) | Semi-trusted | Protected by TLS; still exposed to interception, replay, and availability attacks if implemented incorrectly |
| Network channel (App ↔ AI Proxy) | Semi-trusted | Protected by TLS; session token must be validated server-side on every request |
| Network channel (License Server ↔ Apple / Intel attestation endpoints) | Semi-trusted | Protected by TLS plus pinned vendor root certificates; activation depends on external CA availability |

### Trust Boundary Notes

- The **primary trust anchor on the client** is the TEE-generated private key and the TEE's
  ability to sign a fresh challenge without exposing that private key to normal-world code.
- The **client operating system is explicitly untrusted**. CloseCode is designed under the
  assumption that root access on the client does **not** imply access to TEE-protected keys.
- The **AI Proxy is trusted for policy enforcement and API key custody**, but is intentionally a
  minimal service so that compromise of its logic surface is harder than compromise of a large
  multi-purpose backend.
- The **License Server is a stronger trust boundary than the client**, but its availability is a
  single point of failure because the system is fail-closed and always online.

---

## 3. Attacker Model

### 3.1 Attacker Goals

The attacker is assumed to be financially motivated and attempts to obtain continued access to
CloseCode without purchasing or maintaining a valid license. Concretely, the attacker may try to:

- Run CloseCode without a valid license
- Replay a valid activation or session token on another machine
- Patch the client to skip license enforcement or forge a successful verification result
- Extract secret material from client RAM or proxy RAM
- Impersonate a valid TEE-backed device during activation or per-launch verification
- Intercept, modify, or replay traffic between the App and the License Server / AI Proxy
- Cause denial of service to lock out legitimate users

### 3.2 Attacker Capabilities

The baseline attacker is strong on the client side but not omnipotent:

- Has root/administrator access to the client machine
- Can attach a debugger (`gdb`, `lldb`) or use binary patching and instrumentation tools
- Can read and write arbitrary normal-world process memory on the client
- Can attempt physical-memory corruption or disturbance attacks such as Rowhammer
- Can observe cache timing side channels such as Flush+Reload or Prime+Probe against normal-world code
- Can intercept, drop, delay, or replay network traffic between client and server components
- Can script repeated requests to probe edge cases in activation, nonce handling, and token validation
- Cannot compromise the License Server, AI Proxy, Apple Attestation CA, Intel IAS/DCAP, or AI Model API directly
- Cannot break standard cryptographic primitives such as SHA-256, HMAC-SHA256, ECDSA, or Ed25519
- Cannot directly extract private keys from a correctly functioning Secure Enclave or SGX enclave

### 3.3 Out of Scope

The following are explicitly out of scope for this threat model:

- Physical invasive attacks on TEE hardware (decapping, fault injection against the chip package,
  invasive probing, JTAG on protected internals)
- Vulnerabilities in vendor TEE firmware, Secure Enclave firmware, SGX microcode, or the vendor
  attestation root itself
- Insider threats or social engineering attacks against the developer or hosting provider
- Direct compromise of the License Server infrastructure, AI Proxy infrastructure, or AI Model API
- Denial-of-service mitigation beyond documenting the risk; the project is fail-closed and does not
  attempt high-availability engineering
- Abuse of the LLM output itself (prompt injection into generated code, model hallucinations)
  except where it affects license enforcement

---

## 4. STRIDE Threat Analysis

Status values used below:

- **Mitigated** — the architecture directly addresses the threat with a concrete control
- **Partial** — the threat is reduced but not fully eliminated
- **Unmitigated** — the threat is accepted, out of scope, or only documented

### 4.1 CloseCode App and TEE Boundary

| STRIDE Category | Threat | Severity | Status |
| :--- | :--- | :--- | :--- |
| Spoofing | Attacker forges a device identity by inventing hardware attributes or cloning another machine's visible system identifiers | Critical | Mitigated |
| Spoofing | Attacker replays a previously captured valid session token from the same or another machine | High | Partial |
| Tampering | Attacker patches the App to skip `tee_init()` or to fake a successful license verification result locally | Critical | Mitigated |
| Tampering | Attacker modifies prompt content after signing but before dispatch to the AI Proxy | High | Mitigated |
| Repudiation | Attacker denies having used a specific activation or verification flow | Low | Partial |
| Information Disclosure | Attacker dumps normal-world client RAM to recover the TEE private key | Critical | Mitigated |
| Information Disclosure | Attacker extracts signed payloads, session tokens, or prompt data from normal-world client RAM | High | Partial |
| Denial of Service | Attacker disables the local TEE path or prevents the App from reaching required servers, causing the App to fail closed | Medium | Unmitigated |
| Elevation of Privilege | Control-flow hijack in normal-world code attempts to bypass license enforcement and gain access to the AI Proxy | Critical | Mitigated |

**Rationale and mitigations:**

- Device identity spoofing through MAC address / serial cloning is mitigated because CloseCode no
  longer uses fuzzy hardware fingerprints; it binds the license to a TEE-generated public key and
  activation-time platform attestation.
- Local patching of normal-world code is mitigated because the AI Proxy ultimately requires a valid
  session token and the License Server only issues that token after challenge-response using the
  TEE-backed private key. Patching the UI cannot synthesize the cryptographic proof.
- Prompt tampering after signing is mitigated by the Prompt Pipeline design: AST/RAG enrichment
  happens before signing, and the signed payload is what gets sent onward.
- Disclosure of prompt data and session tokens from normal-world memory remains only **partially**
  mitigated; the TEE protects the device private key, not all application data. A root attacker may
  still read transient prompt material or live session tokens from client RAM.

### 4.2 License Server

| STRIDE Category | Threat | Severity | Status |
| :--- | :--- | :--- | :--- |
| Spoofing | Attacker submits a fake attestation object to activate an untrusted device | Critical | Mitigated |
| Spoofing | Attacker reuses a previously valid activation transcript for a different device | Critical | Mitigated |
| Tampering | Attacker alters activation or verification requests in transit | High | Mitigated |
| Tampering | Attacker reuses or races a nonce to bypass challenge freshness checks | High | Mitigated |
| Repudiation | User denies having activated or deactivated a license on a specific device | Medium | Partial |
| Information Disclosure | Database breach reveals stored device identity material | High | Partial |
| Denial of Service | License Server outage prevents all new sessions because the system is always online and fail-closed | Critical | Unmitigated |
| Elevation of Privilege | Attacker abuses a logic bug to receive session tokens without a valid challenge signature | Critical | Partial |

**Rationale and mitigations:**

- Fake device activation is mitigated by attestation verification against Apple App Attest or Intel
  IAS/DCAP, with vendor root CAs pinned in the Attestation Verifier.
- Replay of stale per-launch proofs is mitigated by single-use nonces plus short TTLs and timestamp
  skew bounds in the challenge-response protocol.
- A License Store breach is only **partially** mitigated: it does not expose private keys, because
  only HMAC(server_secret, device_public_key) is stored, but it may still reveal license metadata
  and enable offline analysis of activation records.
- Availability remains unmitigated by design. ADR-0002 explicitly accepts that a License Server
  outage locks out all clients.

### 4.3 AI Proxy

| STRIDE Category | Threat | Severity | Status |
| :--- | :--- | :--- | :--- |
| Spoofing | Unlicensed client sends requests directly to the AI Proxy without a valid session token | Critical | Mitigated |
| Spoofing | Client reuses an expired or forged session token to impersonate a licensed session | High | Mitigated |
| Tampering | Client attempts to smuggle the session token onward to the AI Model API or alter proxy forwarding semantics | Medium | Mitigated |
| Repudiation | User denies having sent a specific prompt through the AI Proxy | Low | Partial |
| Information Disclosure | Proxy compromise or memory scraping reveals the live AI provider API key | Critical | Partial |
| Information Disclosure | Proxy logs or stores prompt contents unexpectedly | High | Mitigated |
| Denial of Service | Proxy outage prevents all LLM access even for properly licensed users | High | Unmitigated |
| Elevation of Privilege | Logic bug in token validation allows forwarding without successful verification | Critical | Partial |

**Rationale and mitigations:**

- Direct use of the AI Model API is prevented because the API key is never present on the client;
  only the AI Proxy holds it and injects it after session validation.
- Forged or expired tokens are mitigated by signature verification against the License Server public
  key baked into proxy configuration at deploy time.
- Prompt logging is mitigated architecturally: the AI Proxy is intentionally a thin forwarding layer
  that does not parse, persist, or inspect prompt content beyond what is required for forwarding.
- The AI provider API key still exists in proxy process memory during operation, so a sufficiently
  strong compromise of the proxy host would disclose it. This is reduced operationally by keeping
  the service minimal, but not eliminated.

### 4.4 Network Channels

| STRIDE Category | Threat | Severity | Status |
| :--- | :--- | :--- | :--- |
| Spoofing | Attacker impersonates the License Server or AI Proxy with a rogue TLS endpoint | Critical | Partial |
| Tampering | MITM modifies challenges, tokens, or prompt payloads in transit | High | Mitigated |
| Repudiation | Parties dispute what was sent over the network | Low | Partial |
| Information Disclosure | Network observer reads prompts, tokens, or attestation material in transit | High | Mitigated |
| Denial of Service | Attacker blocks network connectivity to force offline behavior | High | Mitigated |
| Elevation of Privilege | Attacker uses transport-layer manipulation to turn an unlicensed state into a licensed one | Critical | Mitigated |

**Rationale and mitigations:**

- Confidentiality and integrity in transit are mitigated by HTTPS/TLS on all external channels.
- The classic "block network to enter offline mode" attack is mitigated by architecture: CloseCode
  has no offline grace path and simply fails closed when required servers are unreachable.
- Server impersonation is only **partially** mitigated unless certificate pinning is consistently
  deployed on every client-server channel. The architecture assumes TLS, but implementation quality
  determines whether a rogue but publicly trusted certificate could be abused.

### 4.5 Microarchitectural Threats

| STRIDE Category | Threat | Severity | Status |
| :--- | :--- | :--- | :--- |
| Information Disclosure | Spectre-style speculative execution leaks secrets from normal-world memory | High | Partial |
| Information Disclosure | Cache timing attacks (Flush+Reload, Prime+Probe) recover prompt material or live session tokens from normal-world code paths | High | Partial |
| Information Disclosure | Cross-core / transient execution attacks against the TEE implementation leak enclave-protected material | Critical | Unmitigated |
| Tampering | Rowhammer-style memory corruption flips state in normal-world code or request buffers | High | Partial |
| Information Disclosure | Cold-boot or RAM scraping attacks recover transient client-side or proxy-side secrets | High | Partial |
| Denial of Service | Microarchitectural disturbance crashes the client or corrupts transient state, preventing use | Medium | Unmitigated |

**Rationale and mitigations:**

- These threats motivated the TEE-first design. The highest-value secret — the device private key —
  is intended to remain inside the Secure Enclave or SGX enclave, reducing the impact of attacks on
  normal-world memory.
- However, prompt contents, session tokens, and other transient data still exist outside the TEE,
  so many disclosure and corruption attacks are only **partially** mitigated rather than eliminated.
- Attacks that break the TEE implementation itself are out of scope. If the Secure Enclave or SGX is
  compromised below the application layer, CloseCode's client-side security assumptions no longer hold.

---

## 5. Residual Risk

After the mitigations above, the following residual risks remain and are explicitly accepted:

1. **Always-online availability dependency**
   - Because CloseCode fails closed and requires live contact with the License Server and AI Proxy,
     outages or network filtering can deny service to legitimate users.
   - This is accepted because offline operation would create a stronger license-bypass path than the
     availability risk it removes.

2. **Prompt and token exposure in normal-world memory**
   - The TEE protects the device private key, but not every application secret. Prompts, AST/RAG
     context, and live session tokens may still exist transiently in untrusted memory on the client.
   - This is accepted because moving the entire application into a TEE is impractical and far beyond
     project scope.

3. **AI provider API key exposure in proxy memory**
   - The AI Proxy must hold the upstream API key in memory to inject it into forwarded requests.
   - This is accepted because the alternative — shipping the API key to the client — would be a much
     weaker design. The residual risk is reduced by keeping the proxy minimal and stateless.

4. **TEE implementation and vendor trust**
   - CloseCode assumes Apple Secure Enclave and Intel SGX provide their documented security
     guarantees, and that vendor attestation roots are trustworthy.
   - This is accepted because a course project cannot defend against firmware- or microcode-level
     compromise of commercial TEEs.

5. **Single-server operational risk**
   - The current architecture does not attempt HA deployment, multi-region failover, or DDoS defense.
   - This is accepted as a deployment limitation rather than a protocol flaw. It should be addressed
     in a production system, but is out of scope for the project.
