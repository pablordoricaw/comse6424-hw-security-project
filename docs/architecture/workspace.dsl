workspace "CloseCode" "C4 architecture model for CloseCode, a license-enforced AI coding agent immune to software and microarchitectural attacks." {

    model {

        user = person "User" {
            description "A vibe-coder who uses CloseCode to edit code via natural language prompts on their local machine."
        }

        closeCode = softwareSystem "CloseCode" {
            description "A node-locked, license-enforced AI coding agent. Requires Apple Silicon (Secure Enclave) or Intel SGX. Enforces that only licensed devices on supported hardware can reach the AI Model API."
            tags "Internal"

            # ──────────────────────────────────────────
            # Containers inside CloseCode
            # ──────────────────────────────────────────
            tui = container "CloseCode App" {
                description "Terminal coding agent. Calls the TEE Module (an in-process platform shim) via the narrow C ABI (cgo) for license verification and prompt signing, then forwards signed prompts to the AI Proxy."
                technology "Go, Bubble Tea, cgo"
                tags "Local" "TUI"

                # ──────────────────────────────────────────
                # Components inside CloseCode App
                # ──────────────────────────────────────────
                tuiRenderer = component "TUI Renderer" {
                    description "Drives the Bubble Tea terminal UI. Accepts raw user input and displays streamed LLM responses. Delegates all business logic to other components."
                    technology "Go, Bubble Tea"
                    tags "Local" "Component"
                }

                licenseManager = component "License Manager" {
                    description "Sole owner of the TEE lifecycle and License Server handshake. Produces signed payloads for outgoing prompts."
                    technology "Go"
                    tags "Local" "Component"
                }

                teeModule = component "TEE Module" {
                    description "In-process C ABI shim (tee_init / tee_sign / tee_destroy). Platform-specific: Swift dylib on Apple Silicon, C/C++ ECALL shim on Intel SGX."
                    technology "Swift @_cdecl · C/C++ + SGX SDK (Intel)"
                    tags "Local" "TEEModule" "Component"
                }

                astEngine = component "AST Engine" {
                    description "[Stub] Parses the codebase into an AST and produces structured file diffs for prompt context enrichment."
                    technology "Go, tree-sitter"
                    tags "Local" "Stub" "Component"
                }

                ragEngine = component "RAG Engine" {
                    description "[Stub] Maintains a local vector index and retrieves top-k relevant code snippets for prompt context enrichment."
                    technology "Go, local embeddings"
                    tags "Local" "Stub" "Component"
                }

                promptPipeline = component "Prompt Pipeline" {
                    description "Enriches the user prompt with AST and RAG context, requests a signature from the License Manager, and dispatches the signed payload to the AI Proxy."
                    technology "Go"
                    tags "Local" "Component"
                }
            }

            licenseServer = container "License Server" {
                description "Verifies TEE attestation at activation, binds the license to the device public key, and issues short-lived signed session tokens per launch."
                technology "Go, HTTPS/TLS"
                tags "Cloud"
            }

            aiProxy = container "AI Proxy" {
                description "Stateless service that validates session tokens and forwards authenticated prompts to the AI Model API with the injected Gemini API key."
                technology "Go, HTTPS/TLS"
                tags "Cloud"
            }
        }

        aiModelApi = softwareSystem "AI Model API" {
            description "A third-party Model-as-a-Service provider (Gemini). Accepts prompt requests forwarded by the CloseCode AI Proxy. Has no awareness of CloseCode license enforcement that is handled upstream."
            tags "External"
        }

        teeAPIApple = softwareSystem "Secure Enclave API" {
            description "Apple's CryptoKit / Security framework. Exposes the Secure Enclave P-256 key pair to the in-process TEE Module shim. The private key never leaves the Secure Enclave chip."
            tags "External" "TEEPlatform"
        }

        teeAPISGX = softwareSystem "Intel SGX SDK" {
            description "Intel's SGX SDK and trusted runtime. The in-process TEE Module C shim issues ECALLs into the signed SGX enclave. The enclave seals key material to MRENCLAVE + platform hardware root."
            tags "External" "TEEPlatform"
        }

        # ──────────────────────────────────────────
        # Relationships — User
        # ──────────────────────────────────────────
        user -> closeCode "Enters natural language prompts to edit code on" "Interactive TUI"
        user -> tui "Enters natural language prompts to edit code on" "Interactive TUI"
        user -> tuiRenderer "Types natural language prompt" "Interactive TUI"

        # ──────────────────────────────────────────
        # Relationships — Component level (inside CloseCode App)
        # ──────────────────────────────────────────
        tuiRenderer -> licenseManager "Triggers license init on startup and destroy on exit" "In-process"
        tuiRenderer -> promptPipeline "Forwards raw user prompt" "In-process"

        licenseManager -> teeModule "Calls tee_init / tee_sign / tee_destroy on" "C ABI via cgo"
        licenseManager -> licenseServer "Sends TEE attestation and signed challenge" "HTTPS/TLS"
        licenseServer -> licenseManager "Returns signed session token" "HTTPS/TLS"

        astEngine -> promptPipeline "Provides AST diff and code structure context to" "In-process"
        ragEngine -> promptPipeline "Provides top-k retrieved code snippets to" "In-process"
        promptPipeline -> licenseManager "Requests signed payload and session token from" "In-process"
        promptPipeline -> aiProxy "Dispatches signed prompt with session token to" "HTTPS/TLS"
        aiProxy -> promptPipeline "Streams LLM response to" "HTTPS/TLS (SSE)"

        teeModule -> teeAPIApple "Performs signing and attestation via in-process TEE Module" "Swift @_cdecl → CryptoKit"
        teeModule -> teeAPISGX "Performs signing and attestation via in-process TEE Module" "C ECALL → SGX SDK"

        # ──────────────────────────────────────────
        # Relationships — AI Proxy ↔ AI Provider
        # ──────────────────────────────────────────
        aiProxy -> aiModelApi "Forwards prompt with injected Gemini API key" "HTTPS/TLS"
        aiModelApi -> aiProxy "Streams LLM response" "HTTPS/TLS (SSE)"

        # ──────────────────────────────────────────
        # Deploy-time trust: License Server public key → Proxy config
        # ──────────────────────────────────────────
        licenseServer -> aiProxy "Provides public key for session token validation" "Deploy-time config"

    }

    views {

        systemContext closeCode "CloseCode-Context" {
            include user
            include closeCode
            include teeAPIApple
            include teeAPISGX
            include aiModelApi
            description "C4 Level 1 — System Context: CloseCode as a single system delivering value to the User. Depends on the AI Model API for LLM inference and on the platform TEE API (Apple Secure Enclave or Intel SGX) for license enforcement."
            autolayout lr
        }

        container closeCode "CloseCode-Container" {
            include user
            include tui
            include licenseServer
            include aiProxy
            include teeAPIApple
            include teeAPISGX
            include aiModelApi
            description "C4 Level 2 — Container: Internal deployable units of CloseCode. The CloseCode App contains an in-process TEE Module shim (detailed at Level 3) that calls the platform TEE API — either Apple CryptoKit / Secure Enclave or Intel SGX SDK."
            autolayout lr
        }

        component tui "CloseCode-App-Components" {
            include user
            include tuiRenderer
            include licenseManager
            include teeModule
            include astEngine
            include ragEngine
            include promptPipeline
            include licenseServer
            include aiProxy
            include teeAPIApple
            include teeAPISGX
            include aiModelApi
            description "C4 Level 3 — Component: Internal components of the CloseCode App. The License Manager is the sole owner of the TEE lifecycle and License Server handshake. AST and RAG Engines enrich prompts with code context before signing and dispatch."
            autolayout lr 50 100
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
            element "Stub" {
                color "#888888"
                fontSize 24
                border "Dashed"
            }
            element "Local" {
                color "#1a5fa8"
                stroke "#1a5fa8"
                fontSize 24
            }
            element "Cloud" {
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
