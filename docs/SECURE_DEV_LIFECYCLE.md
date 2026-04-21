# Secure Development Lifecycle (SDL) for CloseCode <!-- omit from toc -->

## Table of Contents <!-- omit from toc -->

- [Overview](#overview)
- [Why SDL for CloseCode](#why-sdl-for-closecode)
- [The SDL Loop](#the-sdl-loop)
- [Phase 1 — Define Assets](#phase-1--define-assets)
- [Phase 2 — Define the Attacker Model](#phase-2--define-the-attacker-model)
- [Phase 3 — Threat Model the Application](#phase-3--threat-model-the-application)
- [Phase 4 — Design Mitigations Into the Architecture](#phase-4--design-mitigations-into-the-architecture)
- [Phase 5 — Implementation Analysis](#phase-5--implementation-analysis)
- [Phase 6 — Review and Iterate](#phase-6--review-and-iterate)
- [Living Documents](#living-documents)

---

## Overview

CloseCode follows a **Security Development Lifecycle (SDL)** process throughout its design and implementation. The SDL is a software engineering practice that embeds security thinking at every stage of development rather than treating it as a final audit step. This document describes the SDL process as applied to CloseCode and serves as the index connecting each phase to the corresponding design and implementation artifacts.

The SDL process used here is grounded in Microsoft's SDL methodology, adapted for a research and course project context, and applied specifically to the constraints of CloseCode: a fully offline, macOS-only, TEE-backed software licensing system for a local AI coding agent.

---

## Why SDL for CloseCode

CloseCode has an adversarial threat model by design. The user running the application is also the potential attacker — they have root access to the machine, access to standard reverse engineering tools, and a financial incentive to bypass license enforcement. This makes security a first-class concern from the first line of design, not an afterthought.

The instructions for this project explicitly require the design to account for:

- Common software threats: memory corruption, control flow attacks, unsafe parsing or serialization, privilege misuse, and implementation bugs
- Microarchitectural threats: shared resource leakage, speculative execution effects, and software fault injection attacks such as Rowhammer

Addressing these threats systematically — rather than reactively — requires a structured process. The SDL provides that structure.

---

## The SDL Loop

The SDL is not a waterfall. Each phase feeds back into the previous ones as new information is discovered during implementation. The threat model is a **living document** that is revised whenever the implementation reveals new attack surfaces or invalidates earlier assumptions.

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   1. Define Assets                                          │
│        ↓                                                    │
│   2. Define Attacker Model                                  │
│        ↓                                                    │
│   3. Threat Model the Application        ←────────┐        │
│        ↓                                          │        │
│   4. Design Mitigations Into Architecture         │        │
│        ↓                                          │        │
│   5. Implement With Security-Conscious Practices  │        │
│        ↓                                          │        │
│   6. Review Implementation Against Design ────────┘        │
│      (find gaps, update threat model, iterate)             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Phase 1 — Define Assets

**Goal:** be explicit about what is worth protecting before deciding how to protect it.

An asset is anything whose confidentiality, integrity, or availability matters to the security of the system. Assets are the input to the attacker model and the threat model — without a clear asset list, it is impossible to reason about what the attacker is trying to reach.

For CloseCode, assets fall into two categories:

**Functional assets** — things that represent the value the system delivers and that should only be accessible to paying users:
- The AST engine and RAG pipeline functionality (the proprietary capability being licensed)
- Prompt content submitted by the user at runtime

**Security mechanism assets** — things that the license enforcement machinery depends on:
- The device private key held in the Secure Enclave
- The license token stored on disk (proof of activation)
- The license checking code path itself (the gate in front of the functional assets)

The license checking code path is as much an asset as the license data it protects. An attacker who cannot forge a valid license token may still bypass enforcement entirely by subverting the mechanism that checks it.

**Artifact:** `docs/THREAT_MODEL.md` — Assets section

---

## Phase 2 — Define the Attacker Model

**Goal:** scope the attacker's capabilities deliberately so that design effort is concentrated where it matters.

The attacker model answers: who is the attacker, what can they do, and what is out of scope? For CloseCode, the attacker is the user themselves — someone who has purchased a license (or not) and wants to use the application beyond their entitlement. They have physical access to their own machine and root privileges.

CloseCode uses a **two-tier attacker model**:

**Tier 1 — The Realistic Attacker (primary design target)**

This is the attacker whose capabilities the system is designed to fully mitigate. They represent the realistic threat profile for a software licensing system targeting motivated but non-specialist users.

Capabilities:
- Root access to their own Mac
- Standard reverse engineering tools: `lldb`, Hopper, class-dump, Frida
- Ability to copy files, read normal-world process memory, and modify the filesystem
- Ability to run instrumentation against a running process
- System Integrity Protection (SIP) is **enabled** — they have not rebooted into recovery mode

Cannot do:
- Disable SIP (requires deliberate physical intervention: reboot into recovery mode and run `csrutil disable`)
- Extract private keys directly from the Secure Enclave hardware
- Break standard cryptographic primitives (SHA-256, HMAC-SHA256, P-256 ECDSA)
- Compromise the macOS Secure Enclave firmware or the Apple attestation root

**Tier 2 — The Advanced Attacker (document, partially mitigate)**

This is the attacker whose capabilities exceed what CloseCode fully defends against. The design raises the cost of their attacks but accepts residual risk.

Additional capabilities beyond Tier 1:
- Has disabled SIP: can modify system frameworks, inject into Hardened Runtime processes
- Can use Frida unrestricted against system-level targets
- Can perform cache timing side-channel attacks (Flush+Reload, Prime+Probe) against normal-world code
- Can attempt Rowhammer-style fault injection against normal-world memory

Still cannot:
- Physically decap or perform invasive probing of the Secure Enclave chip
- Break cryptographic primitives

**Out of scope entirely:**
- Physical invasive attacks on Secure Enclave hardware
- Compromise of macOS, CryptoKit, or Security.framework itself
- Compiler or toolchain supply chain attacks

**Artifact:** `docs/THREAT_MODEL.md` — Attacker Model section

---

## Phase 3 — Threat Model the Application

**Goal:** systematically enumerate threats against the actual application flow, grounded in the asset list and attacker model.

Threat modeling is performed against the **application data flow**, not against an abstract architecture. For each step in the CloseCode runtime flow, the threat model asks what a Tier 1 or Tier 2 attacker can do at that step using the threat categories required by the project:

**Software threats:**
- Memory corruption — can the attacker corrupt the license check result in memory before it is acted on?
- Control flow attacks — can the attacker redirect execution to skip the license gate?
- Unsafe parsing or serialization — can a malformed license token pass validation due to a parsing bug?
- Privilege misuse — can the attacker abuse macOS APIs or entitlements the app holds?
- Implementation bugs — are there logic errors in the license check that can be exploited?

**Microarchitectural threats:**
- Shared resource leakage — can the attacker observe license check state or AST/RAG content via cache timing?
- Speculative execution effects — can speculative execution expose gated functionality to an attacker observing microarchitectural side channels?
- Software fault injection (Rowhammer) — can the attacker flip bits in the license check result or license token in memory?

The threat model uses **STRIDE** categories (Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege) to organise findings, with each threat tagged by severity and mitigation status.

**Artifact:** `docs/THREAT_MODEL.md` — STRIDE Threat Analysis section

---

## Phase 4 — Design Mitigations Into the Architecture

**Goal:** every architectural decision maps to a specific threat it responds to.

Mitigations are designed into the architecture in response to the threat model output. This means each architectural decision has a documented rationale tied to a specific threat rather than being made for general "good practice" reasons.

Architecture Decision Records (ADRs) in `docs/adr/` capture decisions at this phase. Each ADR states the threat context that motivated the decision, the options considered, the decision made, and the residual risk accepted.

Key architectural decisions for CloseCode at this phase include:
- Platform choice (macOS + Apple Silicon only)
- Language choice (Swift single binary)
- TEE integration approach (direct CryptoKit calls, no ABI shim)
- License token format and storage location
- License gate architecture (where in the call graph the check sits)
- Anti-reversing and binary hardening approach

**Artifact:** `docs/adr/` — Architecture Decision Records, `docs/architecture/` — C4 model

---

## Phase 5 — Implementation Analysis

**Goal:** verify that the implementation realises the security properties assumed in the design, and identify gaps introduced by implementation choices.

As each component is implemented, it is reviewed against the threat model to confirm:

- The implementation does not introduce new attack surface not present in the design
- Memory safety properties assumed in the design actually hold (e.g. Swift safe mode is not disabled)
- Parsing and deserialization of untrusted input (the license token) uses strict typed decoding with no manual byte manipulation
- The license gate is positioned correctly in the call graph — reachable AST/RAG code is not speculatively observable before the gate is passed
- Cryptographic operations use platform-standard APIs (CryptoKit) and not custom implementations

Implementation findings that reveal new threats or invalidate design assumptions are fed back into Phase 3 (threat model update) and Phase 4 (architecture update).

**Artifact:** inline code comments referencing threat model entries, implementation notes in `docs/`

---

## Phase 6 — Review and Iterate

**Goal:** close the loop between design intent and implementation reality.

At each project milestone, a structured review asks:

1. Does the implementation match the architecture documented in Phase 4?
2. Does the threat model still accurately describe the system as built?
3. Have any implementation-level threats emerged that were not in the original model?
4. Are residual risks still accepted, or have new mitigations become available?

Findings from this review update the threat model and may trigger new ADRs. The process is explicitly iterative — the threat model at the end of the project should reflect the system as built, not the system as originally imagined.

**Artifact:** updated `docs/THREAT_MODEL.md`, new ADRs if architectural decisions change

---

## Living Documents

The following documents are produced and maintained through the SDL process. They are living artifacts updated as the project evolves:

| Document | Phase | Purpose |
|:---|:---|:---|
| `docs/SECURE_DEV_LIFECYCLE.md` | All | This document; describes the SDL process |
| `docs/THREAT_MODEL.md` | 1–3, 6 | Assets, attacker model, STRIDE analysis, residual risks |
| `docs/adr/` | 4, 6 | Architecture Decision Records |
| `docs/architecture/workspace.dsl` | 4 | C4 model as code (Structurizr DSL) |
| `docs/CHECKPOINT_1.md` | All | Checkpoint submission combining architecture, threat model, and plan |
