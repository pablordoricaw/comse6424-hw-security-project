# ADR-0011: License Manager as Sole Owner of the TEE Lifecycle

**Date:** 2026-04-20
**Status:** Accepted
**Deciders:** Null and Void

---

## Context

ADR-0005 defines the narrow three-function C ABI (`tee_init`, `tee_sign`,
`tee_destroy`) that the Go App uses to interact with the TEE Module. That ADR
establishes *what* the interface is. This ADR establishes *who* in the Go App
is allowed to call it.

The CloseCode App has six components: TUI Renderer, License Manager, TEE Module,
AST Engine, RAG Engine, and Prompt Pipeline. Of these, three have a plausible
reason to interact with the TEE:

- **License Manager** — manages license verification and session token lifecycle
- **Prompt Pipeline** — assembles and dispatches signed payloads; could call
  `tee_sign` directly per prompt
- **TUI Renderer** — owns the process lifecycle; could call `tee_init` at startup
  and `tee_destroy` at shutdown directly

Allowing multiple components to call the TEE Module directly would widen the
trust boundary surface area that ADR-0005 was designed to keep narrow.

## Decision

The **License Manager is the sole component that calls the TEE Module**. No other
component in the CloseCode App calls `tee_init`, `tee_sign`, or `tee_destroy`
directly.

The License Manager's exclusive responsibilities with respect to the TEE are:

1. **Startup** — calls `tee_init(license_token)` at process startup. On success,
   drives the License Server activation handshake (if first launch) or per-launch
   challenge-response (ADR-0007). Holds the resulting session token in memory for
   the duration of the session.
2. **Per-prompt signing** — when the Prompt Pipeline requests a signed payload,
   the License Manager calls `tee_sign(payload)` and returns the signature and
   session token to the Prompt Pipeline. The Prompt Pipeline never calls `tee_sign`
   directly.
3. **Shutdown** — calls `tee_destroy()` before process exit. The TUI Renderer
   triggers this via the License Manager's shutdown interface — it does not call
   `tee_destroy` directly.

### Why Not Let the Prompt Pipeline Call `tee_sign` Directly?

The Prompt Pipeline is responsible for assembling the payload and dispatching it.
If it also called `tee_sign`, it would need access to the TEE Module, meaning
the signing boundary would be owned by two components. This creates two problems:

- **Auditability:** ADR-0005 states that a security auditor should need to inspect
  exactly three call sites. If the Prompt Pipeline calls `tee_sign`, the number of
  call sites grows with the number of prompt dispatch paths, not with the number
  of TEE operations.
- **Session token coupling:** The session token (held by the License Manager) must
  accompany every signed request. If the Prompt Pipeline owned signing, it would
  also need access to the session token, coupling it to the license lifecycle state
  it has no business knowing about.

### Why Not Let the TUI Renderer Call `tee_init` and `tee_destroy`?

The TUI Renderer owns the process lifecycle (startup and shutdown events). It
would be natural to have it call `tee_init` at startup and `tee_destroy` at
shutdown directly. This is rejected because:

- `tee_init` is not just a lifecycle call — it triggers the License Server
  handshake and materially determines whether the session proceeds or fails.
  Coupling this to the UI layer mixes security-critical initialisation with
  display logic.
- If the TUI Renderer held a reference to the TEE Module, the TEE Module
  would appear as a dependency of the UI layer in the component graph, which
  misrepresents where the trust boundary lives.

Instead, the TUI Renderer calls a `licenseManager.Init()` method at startup
and `licenseManager.Destroy()` at shutdown. The License Manager encapsulates
all TEE interaction behind those two calls.

## Alternatives Considered

- **Prompt Pipeline calls `tee_sign` directly:** Widens the TEE call surface
  and couples prompt dispatch to TEE state. Rejected (see above).
- **TUI Renderer calls `tee_init` / `tee_destroy` directly:** Mixes UI and
  security-critical initialisation logic. Rejected (see above).
- **Dedicated `TEE Orchestrator` component:** A separate component between the
  License Manager and the TEE Module that owns all three calls. This adds a
  layer of indirection with no security benefit — the License Manager is already
  a narrow, single-purpose component. Rejected as over-decomposition.

## Consequences

- **Security:** Exactly three call sites exist in the CloseCode App source code
  where the TEE Module is invoked, all inside the License Manager. This satisfies
  the auditability goal stated in ADR-0005.
- **Separation of concerns:** The Prompt Pipeline knows only that it can ask the
  License Manager for a signed payload. It has no knowledge of TEE internals,
  session token storage, or License Server interactions.
- **Testability:** The TEE Module can be stubbed at the License Manager boundary.
  The Prompt Pipeline, AST Engine, RAG Engine, and TUI Renderer can all be tested
  without a TEE present.
- **Single point of failure:** If the License Manager fails, signing and session
  token management both fail. This is intentional — a license enforcement failure
  should be total, not partial. Consistent with the Fail Closed principle in ADR-0002.
