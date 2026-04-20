# ADR-0012: Prompt Pipeline as the Single Assembly Point for Signed Payloads

**Date:** 2026-04-20
**Status:** Accepted
**Deciders:** Null and Void

---

## Context

The CloseCode App enriches user prompts with two sources of local code context
before sending them to the AI Proxy:

- **AST Engine** — parses the codebase into an AST and produces structured file
  diffs
- **RAG Engine** — retrieves top-k relevant code snippets from a local vector index

Both are stubs in the current implementation (ADR-0001) but are architecturally
wired into the component graph. This ADR documents where in that graph they feed
their output, and why.

Two candidates were considered:

1. **Feed into the Prompt Pipeline** — AST and RAG output is assembled into the
   prompt before it is signed and dispatched. The signed payload includes the
   enriched context.
2. **Feed into the TUI Renderer** — AST and RAG output is displayed to the user
   or appended client-side after signing. The signed payload contains only the
   raw user prompt.

## Decision

AST Engine and RAG Engine output feeds into the **Prompt Pipeline**. The Prompt
Pipeline is the single assembly point where the raw user prompt, AST context,
and RAG context are combined into the final payload before it is signed by the
License Manager and dispatched to the AI Proxy.

The assembly order is:

```
raw_prompt  ←  TUI Renderer
ast_context ←  AST Engine
rag_context ←  RAG Engine
                    │
                    ▼
             Prompt Pipeline
             assembles payload
                    │
                    ▼
             License Manager
             signs payload
             (tee_sign via TEE Module)
                    │
                    ▼
             AI Proxy
             (signed payload + session token)
```

The Prompt Pipeline requests a signature from the License Manager over the
*fully assembled* payload — not over the raw prompt alone. This means the
TEE-produced signature covers the enriched context, not just the user's words.

## Why the Signed Payload Must Include Enriched Context

The core security property of CloseCode's licensing model is that the AI Proxy
can verify that a request originated from a licensed, TEE-backed execution of
CloseCode on a specific device. If the signed payload contains only the raw
prompt and the enriched context is appended after signing:

- The AI Proxy receives a valid signature over the raw prompt, but the actual
  request body sent to the AI model includes unsigned context
- An attacker who can intercept and modify requests in transit (or who has
  compromised the network path after the signature check) can substitute
  arbitrary context without invalidating the signature
- The licensing guarantee degrades from "this specific TEE signed this specific
  request" to "this specific TEE signed this user's words, but the rest of the
  request is unverified"

By signing the fully assembled payload, the TEE's signature covers everything
the AI model will see. The integrity guarantee is total.

## Why Not Feed Into the TUI Renderer

Wiring AST and RAG output to the TUI Renderer would imply they are display
features — data shown to the user in the terminal. They are not. They are
prompt enrichment features whose output is consumed by the AI model, not by
the user. Wiring them to the Renderer would:

- Misrepresent their purpose in the architecture
- Give the Renderer a dual role (display logic + prompt construction), violating
  single responsibility
- Place code context outside the signed trust boundary (see security argument above)

## Alternatives Considered

- **TUI Renderer assembles and appends context after signing:** Simpler control
  flow (the Renderer drives everything) but places enriched context outside the
  signed payload. Rejected on security grounds (see above).
- **License Manager assembles the payload:** The License Manager already owns
  signing; it could also own assembly. Rejected because assembly requires
  knowledge of AST and RAG output formats, coupling the security-critical License
  Manager to AI app feature logic. The Prompt Pipeline is the correct isolation
  boundary between feature logic and security logic.
- **Separate `Payload Builder` and `Dispatcher` components:** The Prompt Pipeline
  could be split into a component that assembles the payload and a component that
  dispatches it. Rejected as over-decomposition for the current scope — both
  responsibilities are cohesive (they operate on the same payload object) and
  the combined component is small.

## Consequences

- **Security:** The TEE signature covers the fully enriched payload. The AI Proxy's
  signature verification provides an end-to-end integrity guarantee over everything
  the AI model receives.
- **Separation of concerns:** The Prompt Pipeline is the only component that knows
  about both the AI app features (AST, RAG) and the security layer (License Manager
  signing). All other components interact with only one side of that boundary.
- **Stub compatibility:** While AST Engine and RAG Engine are stubs, the Prompt
  Pipeline simply assembles a payload with empty context fields. The signing and
  dispatch logic is identical whether or not the stubs are replaced with real
  implementations.
- **Future extensibility:** Additional context sources (e.g., a dependency graph
  engine, a test runner) can be wired into the Prompt Pipeline without touching
  the License Manager, TUI Renderer, or AI Proxy.
