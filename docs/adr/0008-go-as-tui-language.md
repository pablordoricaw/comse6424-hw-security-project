# ADR-0008: Use Go as the TUI Application Language

**Date:** 2026-04-18  
**Status:** Accepted  
**Deciders:** Null and Void

---

## Context

CloseCode requires a terminal UI (TUI) application that:

1. Handles security-sensitive data in memory (license tokens, nonces, session tokens, signed payloads)
2. Integrates with platform-specific TEE modules via C ABI FFI (ADR-0004, ADR-0005)
3. Makes outbound HTTPS requests to the license server and cloud LLM backend (ADR-0002)
4. Must be implemented within a 4-week project timeline by a team with mixed language experience

The candidate languages evaluated were Go, Rust, Zig, and C++.

## Decision

We will use **Go** as the language for the CloseCode TUI application.

The TEE module backends (Apple Secure Enclave and Intel SGX) are implemented in their
platform-native languages (Swift/Objective-C and C/C++ respectively) and exposed via the
narrow three-function C ABI defined in ADR-0005. The Go TUI calls these via `cgo`.

The TUI framework is [**Bubble Tea**](https://github.com/charmbracelet/bubbletea) (Charm),
the production-grade Elm-architecture TUI framework for Go.

## Language Comparison

| Dimension | Go | Rust | Zig | C++ |
| :--- | :--- | :--- | :--- | :--- |
| **C FFI** | `cgo` — functional, some overhead, cross-compilation complexity | `bindgen` + `unsafe` blocks — excellent ecosystem | `@cImport` — first-class, best-in-class C interop | Native — zero friction |
| **Memory safety** | GC — safe by default, no manual memory management | Compile-time borrow checker — strongest guarantee | Safety-mode runtime checks — manual but guarded | Unsafe by default — requires ASAN/UBSAN discipline |
| **TUI ecosystem** | Mature — Bubble Tea is production-grade | Good — Ratatui is well maintained | Sparse — pre-1.0 ecosystem | Sparse — FTXUI exists but less mature |
| **Networking** | Excellent standard library — `net/http` is battle-tested | Excellent — `reqwest`/`tokio` but async complexity | Minimal standard library | Functional but no standard HTTP client |
| **Toolchain** | Excellent — single binary, reproducible builds | Excellent — `cargo` is best-in-class | Good but pre-1.0 | Poor — CMake/Meson fragmentation, std version issues |
| **Team learning curve** | Low — simple language, readable for reviewers | High — borrow checker + async Rust from zero | High — novel comptime model, immature docs | Medium — powerful but footgun-dense |
| **Memory corruption risk** | Low — GC eliminates use-after-free and buffer overflows | Very Low — compile-time enforced | Low-Medium — safety-mode catches most at runtime | High — requires significant discipline and tooling |

## Why Go Over Each Alternative

**vs. Rust:** Rust's borrow checker provides stronger compile-time memory safety guarantees
that directly address the memory corruption threat in the project's threat model. However,
async Rust (required for concurrent license server communication and TUI event handling) is
the hardest part of the language. With no team member having prior Rust experience, the
learning curve cost over a 4-week timeline would directly reduce time available for the
security features that are the actual grading focus. If a team member with Rust experience
joins, this decision should be revisited.

**vs. Zig:** Zig has the best C interop of any modern language and would be a natural fit
for ADR-0004's FFI requirement. However, Zig is pre-1.0, its TUI ecosystem is sparse, and
the team has no prior Zig experience. The productivity cost of building TUI primitives from
scratch outweighs the C interop advantage given the narrow three-function FFI surface (ADR-0005).

**vs. C++:** The toolchain fragmentation (CMake, compiler standard support) and the high risk
of memory corruption bugs in manually managed C++ code are disqualifying given the threat model.
Memory corruption is an explicitly listed threat in `THREAT_MODEL.md`; choosing a language that
makes it easy to introduce such bugs conflicts with the project's security goals.

## Consequences

- **Security:** Go's garbage collector eliminates use-after-free and buffer overflow vulnerabilities
  in the TUI layer. Sensitive in-memory data (nonces, session tokens) should be explicitly zeroed
  after use using `runtime.SetFinalizer` or manual zeroing before GC, since Go's GC does not
  guarantee immediate collection or memory zeroing.
- **FFI:** `cgo` is used exclusively for the three TEE module calls (`tee_init`, `tee_sign`,
  `tee_destroy`). The narrow interface (ADR-0005) limits cgo complexity to a single integration
  file per platform backend. `CGO_ENABLED=1` is required at build time.
- **Cross-compilation:** cgo disables Go's native cross-compilation. Platform-specific binaries
  (Apple Silicon, Intel SGX) must be built on their respective target platforms or via
  platform-specific CI runners.
- **TUI:** Bubble Tea's Elm-architecture model (Model, Update, View) provides a structured,
  testable TUI without requiring async concurrency primitives in the application layer.
  License server communication runs in a background `tea.Cmd` goroutine.
- **Networking:** The standard `net/http` client handles all license server and cloud LLM
  backend communication. TLS certificate pinning for the license server channel is implemented
  via a custom `http.Transport` with a pinned certificate pool.
