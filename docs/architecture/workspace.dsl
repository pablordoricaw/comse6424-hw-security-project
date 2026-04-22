workspace "CloseCode" "C4 architecture model for CloseCode, a fully offline license-enforced AI coding agent immune to software and microarchitectural attacks." {

    model {

        user = person "User" {
            description "A vibe-coder who uses CloseCode to edit code via natural language prompts on their local machine."
        }

        # ──────────────────────────────────────────
        # Context Level Systems
        # ──────────────────────────────────────────
        closeCode = softwareSystem "CloseCode" {
            description "A fully offline, node-locked, license-enforced AI coding agent. Apple Silicon (macOS) only. Enforces that only validly licensed devices can access the proprietary AI enrichment and embedded inference."
            tags "Internal"

            # ──────────────────────────────────────────
            # Container Level
            # ──────────────────────────────────────────
            tui = container "CloseCode App" {
                description "A single, statically linked macOS Swift application protected by Hardened Runtime. Contains all UI, proprietary enrichment logic, and MLX-based LLM inference. No network I/O."
                technology "Swift"
                tags "Local" "TUI"

                # ──────────────────────────────────────────
                # Component Level
                # ──────────────────────────────────────────
                tuiRenderer = component "TUI Renderer" {
                    description "Drives the terminal UI. Accepts raw user input and displays streamed LLM responses."
                    technology "Swift"
                    tags "Local" "Component"
                }

                keychainAdapter = component "Keychain Adapter" {
                    description "Reads/writes the self-signed license token. Protected by macOS Code Signature access controls."
                    technology "Swift, Security.framework"
                    tags "Local" "Component"
                }

                teeModule = component "Secure Enclave Module" {
                    description "Interfaces with the hardware TEE. Performs cryptographic signing (SecKeyCreateSignature) using the hardware-bound private key."
                    technology "Swift, CryptoKit"
                    tags "Local" "TEEModule" "Component"
                }

                licenseGate = component "License Gate" {
                    description "Orchestrates offline activation. Issues cryptographic challenges to the SE Module and verifies them against the Keychain token. Unlocks downstream engines if valid."
                    technology "Swift"
                    tags "Local" "Component"
                }

                astEngine = component "AST Engine" {
                    description "Proprietary Asset: Parses the codebase into an AST and produces structured file diffs. Execution is gated by the License Gate."
                    technology "Swift, tree-sitter"
                    tags "Local" "Component"
                }

                ragEngine = component "RAG Engine" {
                    description "Proprietary Asset: Maintains a local vector index and retrieves top-k relevant code snippets. Execution is gated by the License Gate."
                    technology "Swift"
                    tags "Local" "Component"
                }

                promptPipeline = component "Prompt Pipeline" {
                    description "Enriches the user prompt with AST and RAG context in memory, then passes the structured string to the Inference Engine."
                    technology "Swift"
                    tags "Local" "Component"
                }

                inferenceEngine = component "Embedded Inference Engine" {
                    description "Statically linked Apple MLX wrapper (e.g. mac-mlx or swama). Executes the LLM entirely on-device (GPU/NPU) via in-memory function calls. No loopback network traffic."
                    technology "Swift, MLX"
                    tags "Local" "Component"
                }
            }
        }

        teeAPIApple = softwareSystem "Secure Enclave API" {
            description "Apple's hardware TEE. The private key never leaves the silicon."
            tags "External" "TEEPlatform"
        }

        macOSKeychain = softwareSystem "macOS Keychain" {
            description "The native OS encrypted datastore. Enforces code-signature access controls to prevent unauthorized processes from reading the self-signed license token."
            tags "External" "Store"
        }


        # ──────────────────────────────────────────
        # Relationships — Context & Container Level
        # (Structurizr bubbles up lower-level relationships automatically,
        # but defining high-level ones explicitly ensures clean diagram text)
        # ──────────────────────────────────────────
        user -> closeCode "Enters natural language prompts to edit code on" "Interactive TUI"
        user -> tui "Enters natural language prompts to edit code on" "Interactive TUI"

        closeCode -> teeAPIApple "Requests cryptographic signatures for local license verification from" "Swift API"
        tui -> teeAPIApple "Requests cryptographic signatures for local license verification from" "Swift API"


        # ──────────────────────────────────────────
        # Relationships — Component Level
        # ──────────────────────────────────────────
        user -> tuiRenderer "Types natural language prompt into" "Interactive TUI"

        tuiRenderer -> licenseGate "Triggers startup verification" "In-process"
        tuiRenderer -> promptPipeline "Forwards raw user prompt to" "In-process"

        licenseGate -> keychainAdapter "Retrieves offline license token from" "In-process"
        licenseGate -> teeModule "Requests signature for local challenge from" "In-process"
        teeModule -> teeAPIApple "Invokes hardware signing operation" "CryptoKit"

        licenseGate -> astEngine "Passes derived ephemeral key to decrypt proprietary rule sets, defeating control-flow bypasses" "Cryptographic Binding"
        licenseGate -> ragEngine "Passes derived ephemeral key to decrypt embedding weights, defeating control-flow bypasses" "Cryptographic Binding"

        promptPipeline -> astEngine "Requests AST diffs" "In-process"
        promptPipeline -> ragEngine "Requests context snippets" "In-process"
        promptPipeline -> inferenceEngine "Passes enriched prompt string via memory to" "Swift API"

        inferenceEngine -> tuiRenderer "Yields streamed text tokens to" "AsyncStream"

        keychainAdapter -> macOSKeychain "Reads and writes the self-signed license token" "SecItemAdd / SecItemCopyMatching"

    }

    views {

        systemContext closeCode "CloseCode-Context" {
            include user
            include closeCode
            include teeAPIApple
            include macOSKeychain
            description "C4 Level 1 — System Context: CloseCode as a fully offline application. The LLM is now embedded. Depends only on the platform Secure Enclave API for license enforcement."
            autolayout lr
        }

        container closeCode "CloseCode-Container" {
            include user
            include tui
            include teeAPIApple
            include macOSKeychain
            description "C4 Level 2 — Container: The CloseCode App is a single executable container protecting its proprietary assets and interfacing with the Secure Enclave API."
            autolayout lr
        }

        component tui "CloseCode-App-Components" {
            include user
            include tuiRenderer
            include keychainAdapter
            include teeModule
            include licenseGate
            include astEngine
            include ragEngine
            include promptPipeline
            include inferenceEngine
            include teeAPIApple
            include macOSKeychain
            description "C4 Level 3 — Component: All components are statically linked into a single Swift binary. The LLM runs embedded via MLX, completely eliminating localhost network sniffing."
            autolayout lr
        }

        styles {
            element "Person" {
                shape Person
                background "#2d8c4e"
                color "#ffffff"
                fontSize 24
            }
            element "Internal" {
                background "#1a5fa8"
                color "#ffffff"
                fontSize 24
            }
            element "External" {
                background "#4baed4"
                color "#ffffff"
                fontSize 24
            }
            element "TEEPlatform" {
                background "#7b4fa8"
                color "#ffffff"
                fontSize 24
            }
            element "TEEModule" {
                color "#1a5fa8"
                stroke "#1a5fa8"
                fontSize 24
            }
            element "Component" {
                shape Component
            }
            element "Store" {
                shape Cylinder
            }
            element "Local" {
                color "#1a5fa8"
                stroke "#1a5fa8"
                fontSize 24
            }
            element "TUI" {
                shape Terminal
            }
            relationship "Relationship" {
                fontSize 24
                color "#444444"
                style "Dashed"
            }
        }

    }

}
