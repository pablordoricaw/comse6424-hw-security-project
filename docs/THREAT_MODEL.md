# Threat Model

**Project:** CloseCode — Software License Server Immune to Software and Microarchitectural Attacks  
**Team:** Null and Void  
**Status:** Draft  
**Last Updated:** 2026-04-16

---

## 1. System Overview

> _TODO: Add a short description of CloseCode and the license enforcement mechanism._

---

## 2. Architecture and Trust Boundaries

> _TODO: Insert a Data Flow Diagram (DFD) showing the following components and their trust boundaries:_
> - **Client Machine** — runs the CloseCode TUI binary
> - **License Server** — validates license tokens and issues leases
> - **Cloud LLM Backend** — accepts only requests signed by a valid local binary
> - **Local RAM** — where secrets (decryption keys, license tokens, signing keys) temporarily live

### Trust Boundary Summary

| Component | Trust Level | Notes |
| :--- | :--- | :--- |
| CloseCode TUI binary (on disk) | Untrusted until verified | Encrypted at rest; decrypted only with valid license key |
| Client OS and kernel | Untrusted | Attacker assumed to have root access |
| Client RAM | Untrusted | Subject to Rowhammer, cold boot, and memory scraping |
| License Server | Trusted | Operated by developer; issues cryptographically signed leases |
| Cloud LLM Backend | Trusted | Refuses requests not signed by a valid local execution |
| Network channel (Client ↔ License Server) | Semi-trusted | Encrypted via TLS; subject to MITM if cert pinning absent |

---

## 3. Attacker Model

### 3.1 Attacker Goals

> _TODO: Define what the attacker is trying to achieve. Examples:_
> - Run CloseCode without a valid license
> - Extract the Cloud LLM API signing key from client RAM
> - Bypass the license check without contacting the license server
> - Replay a valid license token on an unlicensed machine

### 3.2 Attacker Capabilities

> _TODO: Define what the attacker can do. Suggested baseline:_
> - Has root/administrator access to the client machine
> - Can attach a debugger (`gdb`, `lldb`) or binary patching tool to the process
> - Can read and write arbitrary physical memory (via Rowhammer or a kernel exploit)
> - Can observe cache timing side-channels (Flush+Reload, Prime+Probe)
> - Can intercept network traffic between the client and license server
> - Cannot compromise the license server or cloud LLM backend directly
> - Cannot break standard cryptographic primitives (AES-256, RSA-2048, Ed25519)

### 3.3 Out of Scope

> _TODO: Define what is explicitly NOT covered by this threat model. Examples:_
> - Physical hardware attacks (decapping, JTAG probing of the client machine)
> - Vulnerabilities in the Trusted OS or TEE firmware
> - Social engineering or insider threats at the license server
> - Denial-of-service attacks against the license server

---

## 4. STRIDE Threat Analysis

> _TODO: For each component in the DFD, enumerate threats using the STRIDE framework._
> - **S**poofing — Can the attacker impersonate a legitimate component?
> - **T**ampering — Can the attacker modify data or code in transit or at rest?
> - **R**epudiation — Can the attacker deny performing an action?
> - **I**nformation Disclosure — Can the attacker read secrets they shouldn't?
> - **D**enial of Service — Can the attacker prevent legitimate use?
> - **E**levation of Privilege — Can the attacker gain capabilities beyond their authorization?

### 4.1 Client Binary

| STRIDE Category | Threat | Severity | Status |
| :--- | :--- | :--- | :--- |
| Tampering | Attacker patches the binary to skip the license check | Critical | TODO |
| Information Disclosure | Attacker dumps process memory to extract the signing key | Critical | TODO |
| Tampering | TOCTOU attack flips license validity flag between check and use | Critical | TODO |
| Elevation of Privilege | Control flow hijack bypasses `check_license()` entirely | Critical | TODO |

### 4.2 License Server Communication

| STRIDE Category | Threat | Severity | Status |
| :--- | :--- | :--- | :--- |
| Spoofing | Attacker replays a captured valid license token on another machine | High | TODO |
| Tampering | Attacker performs MITM to swap license response | High | TODO |
| Information Disclosure | License token intercepted in transit | Medium | TODO |

### 4.3 Microarchitectural Threats

| STRIDE Category | Threat | Severity | Status |
| :--- | :--- | :--- | :--- |
| Information Disclosure | Spectre V1 leaks license key via cache timing during bounds check | Critical | TODO |
| Information Disclosure | Flush+Reload attack recovers signing key from shared cache | High | TODO |
| Tampering | Rowhammer bit flip corrupts license validity check result in RAM | Critical | TODO |
| Information Disclosure | MDS/RIDL leaks secrets across hyperthreading boundaries | High | TODO |

---

## 5. Residual Risk

> _TODO: After all mitigations are implemented, document which threats remain partially or fully unmitigated and justify why they are accepted. This section is required by the project rubric._
