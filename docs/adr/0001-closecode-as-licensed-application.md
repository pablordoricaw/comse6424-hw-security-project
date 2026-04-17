# ADR-0001: Use CloseCode (AI Coding Agent TUI) as the Licensed Application

**Date:** 2026-04-16  
**Status:** Accepted  
**Deciders:** Null and Void

---

## Context

The project requires a concrete application whose execution is gated by the license server.
The application itself is secondary to the security features, but it must have the following properties:

1. It must provide a natural, justified reason for an **always-online** requirement to simplify the license enforcement model.
2. The **local execution** itself must be a valuable, non-trivial asset so that the license check is entangled with execution rather than being a skippable side check.
3. It must be implementable as a lightweight binary (to keep scope focused on security, not application features).

## Decision

We will build **CloseCode**, a terminal UI (TUI) AI coding agent inspired by OpenCode. Its core
functionality relies on a cloud LLM backend, which provides the always-online justification.
The local binary performs proprietary code indexing (AST parsing and RAG chunking) whose output
is cryptographically signed before being sent to the cloud backend. The backend refuses requests
not signed by a valid, licensed local binary execution, entangling the license check with the
local execution.

## Alternatives Considered

- **A generic "Hello World" licensed binary:** Too trivial; does not justify the always-online model
  or provide a realistic attack surface for the licensing mechanism.
- **A locally-running AI model:** Removes the always-online requirement, complicating the Fail Closed
  design and requiring significant compute resources beyond the project's scope.
- **A media player with DRM:** Classic DRM application, but the content decryption model is
  well-trodden; less opportunity for novel microarchitectural mitigation design.

## Consequences

- The always-online requirement enables a strict **Fail Closed** license enforcement model with no
  grace period vulnerability window. See ADR-0002.
- The actual AST parsing and RAG functionality is **lower priority** to implement than the signing
  and encryption mechanisms; a stub implementation is acceptable for the course project.
- The design is realistic and maps to industry DRM patterns (e.g., Adobe Creative Cloud, GitHub Copilot).
- Teams must be careful that the cloud backend validation is not itself the primary security
  boundary — the local license check must remain independently enforced.
