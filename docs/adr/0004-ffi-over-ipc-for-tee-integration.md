# ADR-0004: Use FFI with C ABI over IPC for TEE Module Integration

**Date:** 2026-04-18  
**Status:** Accepted  
**Deciders:** Null and Void

---

## Context

The CloseCode TUI application is written in a high-level systems language (Go, Zig, or C++) while
the TEE integration modules are written in platform-native languages (Swift/Objective-C for Apple
Secure Enclave, C/C++ with Intel SGX SDK for SGX). The TUI must invoke the TEE module to perform
license validation and prompt signing.

Two integration approaches were considered:

1. **FFI with C ABI:** The TEE module is compiled as a shared library exposing a C ABI. The TUI
   calls into it via Foreign Function Interface (FFI). Both components share the same process
   address space.

2. **IPC (JSON or Protobuf over Unix socket/pipe):** The TEE module runs as a separate daemon
   process. The TUI communicates with it via a local socket, serializing requests and responses
   as JSON or Protobuf.

The choice has direct implications for the threat model: both the attack surface of the integration
boundary and the exposure of key material are affected.

## Decision

We will use **FFI with a C ABI** to integrate the TEE module with the TUI.

The TEE module exposes exactly three functions via a C header (see ADR-0005). The TUI links
against the platform-specific TEE module shared library at build time. No serialization layer,
no socket, no daemon process.

## Alternatives Considered

- **IPC with JSON/Protobuf:** The TEE module runs as a long-running daemon listening on a local
  Unix socket. This introduces a socket as an additional attack surface: a local privilege
  escalation vulnerability could allow a malicious process to impersonate the TUI and obtain
  arbitrary message signatures from the license key. Unsafe deserialization of the JSON/Protobuf
  payload is also explicitly listed as a threat in the project rubric. The IPC model also requires
  managing daemon lifecycle (startup, crash recovery, shutdown), adding operational complexity.
  
  **Exception:** Intel SGX's architecture mandates an untrusted runtime that communicates with
  the enclave via ECALLs/OCALLs — this is effectively structured IPC enforced by the SGX
  programming model and is not a design choice. The FFI decision applies to the interface between
  the TUI and the SGX host-side shim, not to the enclave boundary itself.

## Consequences

- **Security:** No serialization parsing layer eliminates the unsafe deserialization attack vector
  at the TUI-TEE boundary. The signing key never crosses a socket or pipe. The attack surface
  of the integration boundary is limited to three well-defined function calls.
- **Memory:** Both TUI and TEE module share the same process address space. A Rowhammer attack
  on the TUI's heap could theoretically be in the same physical DRAM rows as the TEE module.
  This is accepted as residual risk on platforms without hardware TEE support; on TEE-enabled
  platforms the key material lives in the hardware-isolated enclave regardless.
- **Portability:** Every target language (Go via cgo, Zig via `@cImport`, C++ natively) supports
  C ABI FFI. The same C header is implemented by each platform-specific TEE module backend.
- **Complexity:** Single process, single build artifact per platform. No daemon lifecycle management.
