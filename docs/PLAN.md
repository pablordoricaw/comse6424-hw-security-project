# Project Plan

## Overview

This project is divided into four sequential phases: implementing the cryptographic foundation, assembling the functional agent, validating the security and performance claims, and finalizing the academic deliverables.

## Phases

**Phase 1: Cryptographic Binding & Core Architecture (April 22 – April 28)**
Establish the secure foundation of the application. This includes writing the Swift modules for the macOS Keychain Adapter, the Secure Enclave CryptoKit interface, and the AES-256 key derivation logic. The goal is to successfully encrypt dummy assets on disk and decrypt them in memory only upon a valid hardware signature.

**Phase 2: Agent Assembly & Embedded Inference (April 29 – May 4)**
This involves building the TUI Renderer, the Prompt Pipeline, integrating the AST and RAG engine stubs, and embedding the local LLM inference engine (e.g., `mac-mlx` or `swama`) directly into the Swift binary.

**Phase 3: Security Validation (May 5 – May 9)**
Test against the Threat Model by simulating expected fully mitigated attacks (token copying, filesystem tampering, unprivileged loopback sniffing) to verify full mitigation.

**Phase 4: Final Reporting & Packaging (May 10 – May 12)**
Write the final report, recording a demonstration video, cleaning up the codebase, and packaging all source code, and tests for submission.

## Milestones

| # | Milestone | Phase | Verifiable Output |
|:--|:---|:---|:---|
| 1 | Cryptographic Pipeline Functional | Phase 1 | A CLI test executable that successfully wraps an AES key with the Secure Enclave and stores it in the Keychain. |
| 2 | License Gate Enforcement | Phase 1 | The application successfully decrypts a test ruleset when a valid token is present and crashes/fails when the token is tampered with or moved to another Mac. |
| 3 | Embedded LLM Streaming | Phase 2 | The Prompt Pipeline passes an enriched string to the embedded MLX engine and streams the text output to the TUI without opening local network ports. |
| 4 | Security Validation Complete | Phase 3 | A test report documenting the failure of Tier 1 attack simulations and capturing the artifacts of a Tier 2 memory dump proof-of-concept. |
| 5 | Artifact Package Ready | Phase 4 | A ZIP/repository containing the final Swift codebase, Hardened Runtime build scripts, documentation, evaluation results. |

