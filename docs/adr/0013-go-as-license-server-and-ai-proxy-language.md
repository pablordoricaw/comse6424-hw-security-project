# ADR-0013: Use Go as the License Server and AI Proxy Language

**Date:** 2026-04-20  
**Status:** Accepted  
**Deciders:** Null and Void

---

## Context

ADR-0008 selected Go for the CloseCode TUI application. The License Server and AI Proxy
are two separate cloud-side services that must also be implemented. This ADR documents
the language choice for those services and why the reasoning differs from ADR-0008 even
though the conclusion is the same.

The two services have different characteristics from the TUI:

**License Server** requirements:
1. Handles concurrent inbound HTTPS requests (activation and per-launch challenge-response)
2. Manages persistent state in a SQLite database (License Store)
3. Makes outbound HTTPS calls to Apple and Intel attestation CA endpoints at activation time
4. Performs cryptographic operations: HMAC verification, digital signature verification,
   session token signing and verification
5. Must be deployable as a single binary with no runtime dependencies

**AI Proxy** requirements:
1. Handles concurrent inbound HTTPS requests from CloseCode App instances
2. Performs session token signature verification (stateless — no database)
3. Streams SSE responses from the AI Model API back to the App in real time
4. Must be deployable as a single stateless binary
5. Must be operationally simple — no persistent state, no external state dependencies

Neither service requires `cgo` or C ABI FFI (the TEE module is local to the App, not the
server side). This removes the primary constraint that made Rust and Zig more costly in ADR-0008.

## Decision

We will use **Go** for both the License Server and the AI Proxy.

Both services are implemented using Go's standard library (`net/http`, `crypto/...`,
`database/sql`) with minimal third-party dependencies. No TUI framework or C FFI is required.

## Why Go for Cloud Services (Different Reasoning from ADR-0008)

ADR-0008 chose Go primarily because of Bubble Tea's maturity and the cost of learning async
Rust within a 4-week timeline. For the cloud services, those factors do not apply. The
relevant reasons here are:

### 1. Standard library is sufficient

Go's `net/http` server handles concurrent requests with goroutine-per-connection concurrency
without requiring an async runtime. The License Server's request concurrency (one goroutine
per activation or session request) is trivially handled by Go's scheduler. No external
HTTP framework (Gin, Echo, Fiber) is needed — the handlers are thin enough that the
standard `http.ServeMux` suffices.

### 2. Cryptographic operations are well-supported

The License Server requires:
- HMAC-SHA256 (`crypto/hmac`, `crypto/sha256`) for License Store key storage
- ECDSA / Ed25519 signature verification (`crypto/ecdsa`, `crypto/ed25519`) for
  challenge-response verification
- JWT or custom signed token generation and verification (`crypto/rsa` or `crypto/ecdsa`)
  for session tokens

All of these are in Go's standard library with no external dependencies.

### 3. SSE streaming relay is idiomatic in Go

The AI Proxy must stream SSE responses from the AI Model API back to the App without
buffering. Go's `io.Copy` and `http.Flusher` interface handle this idiomatically:

```go
func (h *ForwardingHandler) relay(w http.ResponseWriter, upstream *http.Response) {
    flusher := w.(http.Flusher)
    w.Header().Set("Content-Type", "text/event-stream")
    io.Copy(writerFlusher{w, flusher}, upstream.Body)
}
```

This is the primary implementation complexity of the AI Proxy, and Go handles it cleanly
without requiring async primitives or a streaming framework.

### 4. Single binary deployment, no runtime

Both services compile to a single static binary with `CGO_DISABLED=1` (no cgo needed
on the server side). Deployment is a binary copy or a minimal Docker image (`FROM scratch`
or `FROM gcr.io/distroless/static`). No Go runtime installation, no dependency resolution,
no interpreter.

### 5. Consistent toolchain across the full project

Using Go for all three services means a single `go.work` workspace can manage the TUI,
License Server, and AI Proxy as separate modules. Shared types (session token structure,
request/response schemas) can be defined in a common internal package without a cross-language
serialization layer. CI/CD uses a single Go toolchain for all build, test, and lint steps.

## Language Comparison for Cloud Services

| Dimension | Go | Rust | Python | Node.js |
| :--- | :--- | :--- | :--- | :--- |
| **Concurrency model** | Goroutines — simple, implicit | `async`/`await` + `tokio` — explicit, steep curve | `asyncio` or threads — GIL limits true parallelism | Event loop — good for I/O but single-threaded |
| **Standard library HTTP** | `net/http` — production-grade, no external dep | None — requires `axum`/`actix`/`hyper` | `http.server` — not production-grade | `http` — functional but callback-heavy |
| **Cryptography** | `crypto/...` — standard library, well-audited | `ring`/`rustls` — excellent but external deps | `cryptography` lib — external dep, Python overhead | `crypto` — standard but JS type coercion risks |
| **SSE streaming** | `io.Copy` + `http.Flusher` — idiomatic | `axum` SSE support — good but framework dep | `flask-sse` or manual — fragile | `res.write` + `res.flush` — workable |
| **Binary deployment** | Single static binary, no runtime | Single static binary, no runtime | Requires Python runtime + virtualenv | Requires Node.js runtime + node_modules |
| **Memory safety** | GC — safe, no manual mgmt | Compile-time — strongest guarantee | GC — safe | GC — safe |
| **Team familiarity** | High — same as TUI | Low — no prior experience | Medium | Low |

## Alternatives Considered

- **Rust:** Provides stronger compile-time memory safety guarantees than Go, which is
  meaningful for a service handling cryptographic material. However, async Rust (required
  for a concurrent HTTP server) carries the same learning curve cost identified in ADR-0008.
  The License Server and AI Proxy are simple enough that Go's GC-based safety and
  goroutine concurrency are sufficient. If the team had Rust experience, this would be
  the preferred choice for the License Server specifically.
- **Python (Flask/FastAPI):** Familiar to many developers and rapid to prototype, but
  requires a Python runtime in deployment, has GIL-limited true parallelism, and introduces
  dynamic typing risk in security-sensitive cryptographic verification code. The License
  Server's token verification logic is the wrong place for duck-typed runtime errors.
  Rejected.
- **Node.js:** Event-loop concurrency is well-suited to I/O-bound services like the AI
  Proxy, but the JavaScript type system introduces coercion risks in cryptographic
  comparisons (e.g., `==` vs `===` on HMAC digests). Rejected on type safety grounds
  for security-sensitive code.
- **Separate languages per service:** Using Go for the AI Proxy (I/O-bound, thin) and
  Rust for the License Server (crypto-heavy) would play to each language's strengths.
  Rejected because the toolchain split adds CI/CD complexity and shared type definitions
  would require a serialization boundary with no meaningful security benefit for the
  course project scope.

## Consequences

- **Security:** Go's GC eliminates memory corruption in the server-side cryptographic
  verification code. Sensitive values (HMAC digests, session token signing keys) loaded
  from environment config should be explicitly zeroed after use where the GC timing
  cannot be relied upon. The License Server's signing key is the highest-sensitivity
  value and should be zeroed immediately after each signing operation.
- **No cgo on server side:** Both services set `CGO_ENABLED=0`. This enables true
  cross-compilation and `FROM scratch` Docker images. The FFI complexity documented in
  ADR-0008 does not apply to either service.
- **Shared workspace:** A `go.work` file at the repository root manages the TUI, License
  Server, and AI Proxy as three separate Go modules. Shared internal packages (token
  schema, error codes) live in a `internal/shared` module.
- **SQLite on the License Server:** The License Store uses `mattn/go-sqlite3`, which
  requires `CGO_ENABLED=1` for the License Server specifically (SQLite is a C library).
  This is an exception to the no-cgo rule above, scoped to the License Server's
  `database/sql` driver only. The AI Proxy remains fully cgo-free.
- **Consistency trade-off:** All three services using Go means a single developer can
  move between TUI, License Server, and AI Proxy code without a context switch. This
  is the primary operational benefit for a small team on a short timeline.
