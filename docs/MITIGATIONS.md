# Mitigation Traceability Matrix

> This document maps every identified threat from `THREAT_MODEL.md` to a specific mitigation,
> the ADR that justifies the design decision, and the source code location where it is implemented.
> A threat without a row in this table is an unmitigated risk that must appear in the Residual Risk section.

## Traceability Matrix

> [!TIP]
> | Symbol | Meaning |
> | :--- | :--- |
> | 🔴 Not Started | Threat identified, no mitigation implemented yet |
> | 🟡 In Progress | Mitigation partially implemented or under review |
> | 🟢 Implemented | Mitigation fully implemented and referenced in code |
> | ⚪ Accepted Risk | Explicitly accepted as residual risk with justification in THREAT_MODEL.md |

| # | Threat (from THREAT_MODEL.md) | Mitigation Technique | ADR Reference | Code Reference | Status |
| :- | :--- | :--- | :--- | :--- | :--- |
| 1 | Binary patching to skip license check | Encrypt application binary at rest; decrypt only with valid license key | TODO | TODO | 🔴 Not Started |
| 2 | Memory dump to extract signing key | Zero-out key material immediately after use; use `mlock` + `madvise(MADV_DONTDUMP)` | TODO | TODO | 🔴 Not Started |
| 3 | TOCTOU flip of license validity flag | Entangle license key with execution: key *is* the decryption key for the binary | TODO | TODO | 🔴 Not Started |
| 4 | Control flow hijack bypassing `check_license()` | Software CFI via compiler instrumentation (LLVM CFI or `-fsanitize=cfi`) | TODO | TODO | 🔴 Not Started |
| 5 | License token replay on unlicensed machine | Hardware fingerprint bound into license token (MAC address + CPU serial) | TODO | TODO | 🔴 Not Started |
| 6 | MITM on license server response | TLS with certificate pinning on client | TODO | TODO | 🔴 Not Started |
| 7 | Spectre V1 leaking license key | `lfence` barriers after bounds checks; constant-time comparison for license validation | TODO | TODO | 🔴 Not Started |
| 8 | Flush+Reload recovering signing key | Disable shared memory mappings for key material; use dedicated memory region | TODO | TODO | 🔴 Not Started |
| 9 | Rowhammer bit flip on license check result | Guard pages around license check data structures; double-checked locking with redundant copies | TODO | TODO | 🔴 Not Started |
| 10 | MDS/RIDL leakage across hyperthreads | `VERW` instruction flush before context switch; disable HT if performance allows | TODO | TODO | 🔴 Not Started |

Step 1: The Vendor's Desk (Before the user even downloads the app)

Before you (the vendor) ship CloseCode to a user, you need to protect the AST and RAG engines.

    You generate a random, 256-bit symmetric key. Let's call it the Master_AES_Key.

    You use this Master_AES_Key to encrypt the AST rulesets and RAG embeddings.

    You compile the CloseCode application with these encrypted assets inside it.

    When a user buys the software, you generate a License Certificate for them. This certificate contains their license_id, an expiration_date, and—crucially—a copy of the Master_AES_Key.

    You sign this entire License Certificate with your private Vendor Key so nobody can tamper with it, and you email it to the user.

Step 2: First Launch (Offline Activation & Binding)

The user downloads CloseCode, opens it, and inputs their License Certificate. The app is completely offline. Here is how the app "binds" the software to the hardware:

    Verification: The License Gate checks the Vendor Signature on the certificate to ensure you actually issued it. It sees the certificate is valid.

    Hardware Key Generation: The License Gate asks the Mac's Secure Enclave to generate a brand new Key Pair.

        The Private Key is permanently burned into the Mac's silicon.

        The Public Key is given back to the License Gate.

    The Binding (Key Wrapping): The License Gate extracts the Master_AES_Key from the user's License Certificate. It then uses the Secure Enclave's Public Key to encrypt (wrap) the Master_AES_Key. We will call this the Wrapped_AES_Key.

    Storage: The License Gate deletes the original License Certificate from memory. It creates the local License Token containing the Wrapped_AES_Key and saves it into the macOS Keychain.

At this point, the activation is finished. The Master_AES_Key is now cryptographically bound to this specific Mac's hardware.
Step 3: Daily Execution (The "Unpacking")

It is three days later. The user opens CloseCode to do some work. The app needs to decrypt the AST and RAG engines to function.

    Retrieval: The License Gate securely reads the License Token from the macOS Keychain. It pulls out the Wrapped_AES_Key.

    The Hardware Unlock: The License Gate hands the Wrapped_AES_Key down to the Secure Enclave Module and says: "Decrypt this."

    Decryption: Because the Secure Enclave is the only place in the universe that holds the matching Private Key, it successfully decrypts the payload and hands the plaintext Master_AES_Key back to the License Gate in memory.

    Engine Initialization: The License Gate passes the Master_AES_Key to the AST and RAG engines. The engines use it to decrypt their proprietary rulesets in RAM.

    Ready: The Prompt Pipeline can now query the AST and RAG engines.
