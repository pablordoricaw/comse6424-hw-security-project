# Project Plan

**Project:** CloseCode — Software License Server Immune to Software and Microarchitectural Attacks  
**Team:** Null and Void  
**Last Updated:** 2026-04-20

---

## Overview

CloseCode is implemented in three phases, each ending in a verifiable milestone. Phase 1
delivers a working end-to-end system on Apple Silicon. Phase 2 hardens and validates the
security properties of that system. Phase 3 extends coverage to Intel SGX.

All implementation work follows the architecture decisions recorded in `docs/adr/`.
The verification strategy is integrated into each phase rather than deferred to the end.

---

## Repository Structure

```
comse6424-hw-security-project/
├── cmd/
│   ├── closecode/          # CloseCode App entrypoint (Go)
│   ├── license-server/     # License Server entrypoint (Go)
│   └── ai-proxy/           # AI Proxy entrypoint (Go)
├── internal/
│   ├── shared/             # Shared types: token schema, error codes, request/response structs
│   ├── tee/                # TEE Module C ABI shim and platform backends
│   │   ├── apple/          # Swift @_cdecl Secure Enclave backend
│   │   └── sgx/            # C/C++ ECALL SGX enclave backend (Phase 3)
│   ├── license/            # License Manager logic
│   ├── prompt/             # Prompt Pipeline, AST Engine stub, RAG Engine stub
│   ├── server/             # License Server: HTTP Handler, Activation, Session, Attestation, Store
│   └── proxy/              # AI Proxy: HTTP Handler, Token Validator, Forwarding Handler
├── tee/
│   ├── apple/              # Xcode project / Swift package for Secure Enclave dylib
│   └── sgx/                # SGX enclave project (Phase 3)
├── infra/
│   ├── Pulumi.yaml         # Pulumi project definition
│   ├── Pulumi.dev.yaml     # Stack config (example)
│   └── main.go             # Pulumi Go program: GCP VMs, firewall rules, instance metadata
├── docs/
│   ├── adr/                # Architecture Decision Records
│   ├── architecture/       # Structurizr DSL workspace
│   ├── PLAN.md             # This file
│   ├── THREAT_MODEL.md     # STRIDE threat model
│   └── DEMO_SCRIPT.md      # Demo walkthrough (written in Phase 2)
├── scripts/
│   └── smoke-test.sh       # End-to-end smoke test against live servers
├── go.work                 # Go workspace: closecode, license-server, ai-proxy, infra modules
└── Makefile                # Top-level build, test, lint, and deploy targets
```

---

## Milestones

| # | Milestone | Phase | Verifiable Output |
|:--|:---|:---|:---|
| M1 | Go workspace and module scaffold | 1 | `go build ./...` passes across all three modules |
| M2 | License Server core (activation + session) | 1 | Integration test: activate, challenge, verify |
| M3 | AI Proxy core (token validation + forwarding) | 1 | Integration test: valid token forwarded, invalid rejected |
| M4 | Apple Secure Enclave TEE Module | 1 | Unit test: tee_init, tee_sign, tee_destroy against real Secure Enclave |
| M5 | CloseCode App TUI — happy path | 1 | Manual: full activation → prompt → LLM response end-to-end on Apple Silicon |
| M6 | Apple Attestation CA verification | 1 | Integration test: activation rejected without valid App Attest attestation |
| M7 | Security validation — Apple Silicon | 2 | All security validation tests pass (see Phase 2) |
| M8 | Demo script and deployment | 2 | Live GCP deployment; smoke test passes; demo recorded |
| M9 | Intel SGX TEE Module | 3 | Unit test: tee_init, tee_sign, tee_destroy inside SGX enclave |
| M10 | Intel IAS verification + end-to-end SGX | 3 | Full activation → prompt → LLM response end-to-end on SGX hardware |

---

## Phase 1: End-to-End System on Apple Silicon

Goal: a working CloseCode system where a licensed Apple Silicon user can activate, launch,
and send a prompt that reaches Gemini and streams a response back. Intel SGX is deferred.

### Step 1.1 — Repository and module scaffold

- Initialise `go.work` with three modules: `closecode`, `license-server`, `ai-proxy`
- Create `internal/shared` with shared types: `SessionToken`, `ActivationRequest`,
  `ChallengeRequest`, `VerifyRequest`, error codes
- Add top-level `Makefile` with targets: `build`, `test`, `lint`, `deploy`
- Confirm `go build ./...` is clean across all modules
- **Output:** M1

### Step 1.2 — License Server: HTTP Handler and Activation Service

- Implement `internal/server/handler.go` — `net/http` router for `/activate`,
  `/deactivate`, `/challenge`, `/verify`
- Implement `internal/server/activation.go` — Activation Service:
  - Accept `(license_id, device_public_key, platform_attestation)`
  - Stub attestation verification (returns `true`) for now
  - Persist `HMAC(server_secret, device_public_key)` and `license_id` to SQLite
- Implement `internal/server/store.go` — License Store with `mattn/go-sqlite3`:
  schema: `license_id TEXT PRIMARY KEY, device_key_hmac TEXT, status TEXT`
- Write integration test: activate a device, confirm record in store
- **Output:** partial M2

### Step 1.3 — License Server: Session Service

- Implement `internal/server/session.go` — Session Service:
  - `/challenge`: generate 32-byte random nonce, store in in-process TTL map (60s TTL),
    return nonce
  - `/verify`: verify nonce exists and not expired; verify ECDSA/Ed25519 signature
    over `SHA-256(nonce || timestamp || license_id)` against stored device public key;
    issue signed session token (ECDSA, short-lived, 1-hour TTL)
- Implement session token signing and verification in `internal/shared/token.go`
- Write integration test: full challenge → verify flow with a test key pair
- **Output:** M2

### Step 1.4 — AI Proxy

- Implement `internal/proxy/handler.go` — single `POST /v1/prompt` endpoint
- Implement `internal/proxy/validator.go` — Token Validator:
  - Load License Server public key from `LICENSE_SERVER_PUBLIC_KEY` env var at startup
  - Verify session token signature; reject expired tokens; fail closed
- Implement `internal/proxy/forwarder.go` — Forwarding Handler:
  - Strip session token from request
  - Inject `Authorization: Bearer $GEMINI_API_KEY` header
  - Relay to Gemini API endpoint
  - Stream SSE response back via `io.Copy` + `http.Flusher`
- Write integration test: valid token forwarded, tampered token rejected, expired token
  rejected
- **Output:** M3

### Step 1.5 — Apple Secure Enclave TEE Module

- Create `tee/apple/` Swift package exposing three `@_cdecl` functions:
  - `tee_init(license_id: UnsafePointer<CChar>) -> Int32` — generates or loads
    P-256 key pair in Secure Enclave; produces App Attest attestation object
  - `tee_sign(payload: UnsafePointer<UInt8>, len: Int, out: UnsafeMutablePointer<UInt8>,
    out_len: UnsafeMutablePointer<Int>) -> Int32` — signs payload with Secure Enclave
    private key
  - `tee_destroy() -> Int32` — zeroes in-memory state
- Build as a dylib; expose C header `tee.h`
- Implement `internal/tee/apple/` cgo bridge in Go calling the dylib via `tee.h`
- Write unit test calling all three functions against the real Secure Enclave on an
  Apple Silicon machine
- **Output:** M4

### Step 1.6 — License Manager and CloseCode App TUI

- Implement `internal/license/manager.go` — License Manager:
  - On startup: call `tee_init()`, send activation request (or skip if already activated),
    send challenge → verify flow, receive and cache session token
  - Expose `SignPayload(payload []byte) ([]byte, error)` to the Prompt Pipeline
  - On shutdown: call `tee_destroy()`
- Implement `internal/prompt/pipeline.go` — Prompt Pipeline:
  - Accept raw user prompt
  - Call AST Engine stub and RAG Engine stub for context (return empty for now)
  - Call `licenseManager.SignPayload()` on the enriched payload
  - Send signed payload + session token to AI Proxy
  - Stream SSE response to TUI Renderer
- Implement `cmd/closecode/main.go` — Bubble Tea TUI with two states:
  `Activating` and `Ready`
- Manual end-to-end test on Apple Silicon: activate → enter prompt → see Gemini
  response stream in terminal
- **Output:** M5

### Step 1.7 — Apple Attestation CA verification

- Implement `internal/server/attestation.go` — Attestation Verifier:
  - For Apple: verify App Attest certificate chain against pinned Apple root CA
    (`attest.apple.com`)
  - Replace the stub `return true` from Step 1.2
- Write integration test: activation with a real App Attest object succeeds; activation
  with a tampered or missing attestation is rejected with `403`
- **Output:** M6

---

## Phase 2: Security Validation and Deployment

Goal: validate the security properties of the Phase 1 system against the threat model,
deploy to GCP, and produce the demo.

### Step 2.1 — Security validation suite

Each test below maps directly to a threat in `THREAT_MODEL.md`.

#### Functional correctness baseline

| Test | Expected result |
|:---|:---|
| Full activation → challenge → verify → prompt → response | Success |
| Second activation attempt for same device | Idempotent (returns existing binding) |
| Deactivation then re-activation | New binding created |

#### License bypass attempts

| Test | Expected result |
|:---|:---|
| Send request to AI Proxy with no session token | `401` |
| Send request to AI Proxy with expired session token | `401` |
| Send request to AI Proxy with session token signed by a different key | `401` |
| Replay a previously used nonce in `/verify` | `401` (nonce consumed) |
| Submit `/verify` with a timestamp outside ±60s skew | `401` |
| Submit `/verify` with a signature over a different payload | `401` |

#### Device binding

| Test | Expected result |
|:---|:---|
| Use a device public key that is not registered | `403` on `/verify` |
| Attempt to activate with a fake attestation object (no App Attest) | `403` |
| Attempt to activate with a tampered attestation (valid cert chain, wrong key) | `403` |

#### Transport security

| Test | Expected result |
|:---|:---|
| Connect to License Server without TLS | Connection refused |
| Connect to AI Proxy without TLS | Connection refused |

#### Memory / key boundary (manual, Apple Silicon)

| Test | Method | Expected result |
|:---|:---|:---|
| Attach `lldb` to CloseCode App process and attempt to read device private key | Debugger memory inspection | Key not readable in normal-world memory |
| Dump process memory of CloseCode App while signing | `vmmap` + memory read | Private key bytes not present outside TEE boundary |

- **Output:** M7 — all tests pass and results documented in a validation table

### Step 2.2 — GCP deployment with Pulumi

- Initialise `infra/` as a Pulumi Go project (`pulumi new gcp-go`); add to `go.work`
- Implement `infra/main.go` using the Pulumi Go SDK to declare:
  - Two Compute Engine VMs in `us-east1`: License Server VM and AI Proxy VM
  - Firewall rules: allow HTTPS (443) inbound to each VM; deny all other inbound
  - Instance metadata / startup scripts to install the Go binary and register a
    `systemd` service unit for each server
  - Secrets injected via Pulumi config (`pulumi config set --secret`):
    `SERVER_SECRET`, `LICENSE_SERVER_PRIVATE_KEY`, `LICENSE_SERVER_PUBLIC_KEY`,
    `GEMINI_API_KEY`
- Validate infrastructure with `pulumi preview` before applying
- Bring up the stack with `pulumi up`
- Write `scripts/smoke-test.sh`:
  - Run the full activation → challenge → verify → prompt → response flow against live
    GCP servers
  - Assert HTTP response codes and non-empty response body
- Run smoke test against deployed stack; confirm all assertions pass
- **Output:** M8 (deployment)

### Step 2.3 — Demo script

- Write `docs/DEMO_SCRIPT.md` covering:
  1. Show system architecture diagram (C4 deployment view)
  2. Cold start on Apple Silicon: activation flow with TEE key generation
  3. Per-launch challenge-response: show nonce and signature in logs
  4. Prompt → LLM response in the TUI
  5. License bypass attempt: show `401` when session token is missing
  6. Memory key boundary: show that `lldb` cannot read the private key
- **Output:** M8 (demo)

---

## Phase 3: Intel SGX Extension

Goal: extend the Phase 1/2 system to support Intel SGX as a second TEE backend.
Phase 3 is additive — no Phase 1/2 code is modified, only new backends and
verification paths are added.

### Step 3.1 — Intel SGX TEE Module

- Create `tee/sgx/` SGX enclave project (Intel SGX SDK, C/C++):
  - Enclave exposes three ECALLs mirroring `tee_init`, `tee_sign`, `tee_destroy`
  - Key material: Ed25519 key pair sealed to `MRENCLAVE` + platform hardware root
  - Produces an SGX quote for IAS submission at activation time
- Implement `internal/tee/sgx/` cgo bridge calling the SGX enclave via the SDK's
  untrusted runtime
- Write unit test calling all three ECALLs against real SGX hardware
- **Output:** M9

### Step 3.2 — Intel IAS verification

- Extend `internal/server/attestation.go` — add Intel IAS verification path:
  - Submit SGX quote to `api.trustedservices.intel.com/sgx/attestation/v4/report`
    using an IAS API key
  - Verify the IAS report signature against the pinned Intel root CA
  - Confirm `isvEnclaveQuoteStatus` is `OK` or `SW_HARDENING_NEEDED`
- Write integration test: SGX activation with a real quote succeeds; tampered quote
  rejected
- **Output:** partial M10

### Step 3.3 — TEE backend selection at runtime

- Extend `internal/tee/` with a platform detection function:
  - Apple Silicon detected → load Apple Secure Enclave backend
  - Intel + SGX detected → load SGX enclave backend
  - Neither → abort with `CloseCode requires Apple Silicon or Intel SGX`
- Update `internal/license/manager.go` to call the platform-selected backend
- Manual end-to-end test on Intel SGX hardware: activate → prompt → LLM response
- **Output:** M10

---

## Verification Strategy Summary

### Levels of verification

| Level | What is verified | Method |
|:---|:---|:---|
| Unit | Individual functions and components in isolation | `go test` with table-driven tests |
| Integration | Cross-component flows (activation, session, proxy forwarding) | `go test` against a test server instance |
| Security validation | Threat model controls — bypass attempts, replay, token forgery | Scripted negative-path tests (see Phase 2) |
| Manual | TEE memory boundary, debugger inspection, TUI behaviour | Documented manual steps on target hardware |
| Infrastructure | GCP resource definitions correct before apply | `pulumi preview` against target GCP project |
| Smoke | End-to-end against live GCP deployment | `scripts/smoke-test.sh` |

### Coverage targets

- **License Server:** all HTTP endpoints covered by integration tests; all error paths
  covered by negative-path tests
- **AI Proxy:** token validation logic covered by unit tests; forwarding covered by
  integration test with a mock upstream
- **TEE Module:** `tee_init`, `tee_sign`, `tee_destroy` covered by unit tests on real
  hardware for each platform backend
- **Security validation:** every threat in `THREAT_MODEL.md` marked `Mitigated` or
  `Partial` has a corresponding test; `Unmitigated` threats are documented as accepted
  risk with no test

### Hardware requirements

| Phase | Hardware needed |
|:---|:---|
| Phase 1 — 2 | Apple Silicon Mac (M1 or later) for TEE Module and manual validation |
| Phase 3 | Intel Xeon or vPro machine with SGX enabled in BIOS |
| GCP deployment | Any machine with Pulumi CLI, Go toolchain, gcloud CLI, and GCP project access |

### What is explicitly not tested

- Vendor TEE firmware correctness (out of scope per threat model)
- High-availability or failover behaviour of the License Server
- LLM output quality or correctness
- AMD or non-SGX Intel platforms (unsupported by design, per ADR-0006)
