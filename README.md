<h1 align="center">CloseCode</h1>

<p align="center">The <s>open</s> closed source AI coding agent.</p>

<p align="center">
  <a href="https://github.com/pablordoricaw/columbia-ms-courses-home" target="_blank" rel="noopener noreferrer">
    <img src="https://img.shields.io/badge/github-columbia%20courses%20home-blue?style=flat-square&logo=github&color=%236CACE4" alt="GitHub Repository of Columbia Courses Taken">
  </a>
  <img alt="License: Proprietary" src="https://img.shields.io/badge/license-proprietary-red?style=flat-square" />
  <img alt="Access: Denied" src="https://img.shields.io/badge/access-denied-black?style=flat-square" />
  <img alt="Platform: macOS Apple Silicon" src="https://img.shields.io/badge/platform-macOS%20Apple%20Silicon-lightgrey?style=flat-square&logo=apple" />
</p>

> CloseCode is a final project for the **COMSE-6424 Hardware Security** course at Columbia University,
> built under the *Licensed Software Application Immune to Software and Microarchitectural Attack* project option.
> Unlike OpenCode, this one will cost you — and it *knows* if you haven't paid.

- **Team:** Null and Void
  - Pablo Ordorica Wiener ([@pablordoricaw](www.github.com/pablordoricaw))
- **Semester:** Spring 2026
- **Instructor:** Simha Sethumadhavan
- **TA:** Ryan Piersma

---

## What It Does

CloseCode is a terminal-based AI coding agent that enforces software licensing entirely offline using Apple Silicon hardware security primitives. It demonstrates that licensing can be cryptographically bound to a specific device — without any network calls, license servers, or always-online requirements.

The core security claim: **bypassing the license check in software is not sufficient to access the proprietary functionality.** The encrypted AST and RAG engines only decrypt if the Secure Enclave successfully unwraps the master AES key — a hardware operation that cannot be replicated on another machine.

## Architecture

CloseCode is built as a Swift Package with the following modules:

| Module | Description |
|---|---|
| `CloseCode` | Main entrypoint — activation, use, and deactivation flows |
| `LicenseGate` | Orchestrates license validation, Keychain adapter, and SE module |
| `TUI` | Terminal UI renderer (TUIkit) with scrollable prompt output |
| `PromptPipeline` | Decrypts and `dlopen`s AST + RAG dylibs; assembles enriched prompts |
| `GenerateCert` | Vendor tool to produce signed `LicenseCertificate` JSON files |
| `GetFingerprint` | Reads the device `IOPlatformUUID` for cert generation |

### Security Flow

```
License Certificate (vendor-signed JSON)
        │
        ▼
  License Gate ──► IOPlatformUUID check (IOKit)
        │
        ▼
  Secure Enclave ──► Generate non-exportable P-256 key pair
        │               Wrap Master AES Key with SE public key
        ▼
  macOS Keychain ──► Store License Token (Wrapped AES Key + metadata)
        │               kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ▼
  On every launch:
  Keychain → License Gate → SE unwrap → Master AES Key (in memory only)
        │
        ▼
  PromptPipeline ──► AES-GCM decrypt ast.bundle + rag.bundle
        │               dlopen into temp file → delete → dlsym
        ▼
  TUI ──► User prompt → enriched context → output
```

## Requirements

- macOS 14+ on Apple Silicon (Secure Enclave required)
- [swiftly](https://www.swift.org/install/macos/) with Swift 6.0+ toolchain
- A valid `LicenseCertificate` issued for your device

## Usage

### 1. Get your device fingerprint

```bash
swiftly run swift run get-fingerprint
```

### 2. Generate a license certificate (vendor side)

```bash
swiftly run swift run generate-cert \
    --fingerprint <IOPlatformUUID> \
    --expiration <YYYY-MM-DD> \
    --master-key <path/to/master_aes.key> \
    --vendor-key <path/to/vendor_private.pem> \
    --out license.cert
```

### 3. Activate CloseCode on your device

```bash
swiftly run swift run closecode --activate license.cert
```

### 4. Run CloseCode

```bash
swiftly run swift run closecode
```

### 5. Deactivate (removes SE key and Keychain token)

```bash
swiftly run swift run closecode --deactivate
```

### TUI Commands

| Command | Description |
|---|---|
| `<prompt>` | Submit a prompt through the enrichment pipeline |
| `/status` | Show license details and device fingerprint |
| `/help` | Show available commands |
| `/clear` | Clear the output pane |
| `/exit` | Quit CloseCode |

**Scroll keybindings:** `↑/↓` or `Ctrl+K/L` (line), `Ctrl+U/D` (half-page), `Ctrl+G` (bottom), `Ctrl+Shift+G` (top)

## Security Validation

Phase 3 attack simulations verify all Tier 1 (Motivated Competitor) mitigations:

```bash
chmod +x scripts/simulate-attacks.sh
./scripts/simulate-attacks.sh license.cert
```

| Attack | STRIDE Category | Result |
|---|---|---|
| License token copy to another machine | Spoofing / EoP | ✅ Mitigated |
| Encrypted bundle filesystem tampering | Tampering | ✅ Mitigated |
| Keychain token corruption | Tampering | ✅ Mitigated |
| Cold start with no license token | Denial of Service | ✅ Mitigated |
| Expired license certificate | Tampering | ✅ Mitigated |

Tier 2 (Security Researcher) residual risks are documented and accepted in [`docs/CHECKPOINT_1.md`](docs/CHECKPOINT_1.md#residual-risk).

## Project Structure

```text
comse6424-hw-security-project/
├── Package.swift
├── Sources/
│   ├── CloseCode/          # Main entrypoint and Resources (ast.bundle, rag.bundle)
│   ├── TUI/                # Terminal UI renderer
│   ├── LicenseGate/        # License Gate, Keychain Adapter, Secure Enclave Module
│   ├── PromptPipeline/     # Encrypted dylib loading and prompt enrichment
│   ├── GenerateCert/       # Vendor cert generation tool
│   └── GetFingerprint/     # Device fingerprint utility
├── Tests/
│   └── LicenseTests/       # Unit tests for cryptographic binding and token parsing
├── assets/                 # AST and RAG engine Swift source + build outputs
├── docs/
│   ├── adr/                # Architecture Decision Records
│   ├── architecture/       # Structurizr C4 DSL workspace
│   ├── figs/               # C4 diagrams
│   ├── CHECKPOINT_1.md     # Threat model and STRIDE analysis
│   ├── THREAT_MODEL.md
│   ├── MITIGATIONS.md
│   └── SECURE_DEV_LIFECYCLE.md
├── scripts/
│   ├── encrypt-assets.sh   # Build, sign, and AES-GCM encrypt AST/RAG dylibs
│   ├── simulate-attacks.sh # Phase 3 Tier 1 attack simulation suite
│   └── tmux-setup.sh       # Dev environment layout
└── logs/
    └── attack-simulation.log
```

## License

Proprietary. All rights reserved. Your machine has already been fingerprinted.
