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

                # ──────────────────────────────────────────
                # Components inside License Server
                # ──────────────────────────────────────────
                httpHandler = component "HTTP Handler" {
                    description "REST API surface. Routes /activate, /deactivate, /challenge, and /verify over HTTPS/TLS. Performs request validation and delegates to Activation or Session Service."
                    technology "Go, net/http"
                    tags "Cloud" "Component"
                }

                activationService = component "Activation Service" {
                    description "Handles first-time device binding and deactivation. Validates the license ID, invokes the Attestation Verifier, and persists HMAC(server_secret, device_public_key) to the License Store."
                    technology "Go"
                    tags "Cloud" "Component"
                }

                sessionService = component "Session Service" {
                    description "Handles the per-launch challenge-response flow. Issues a single-use nonce, verifies the TEE-signed challenge, and returns a short-lived signed session token. In-process TTL nonce map for anti-replay."
                    technology "Go"
                    tags "Cloud" "Component"
                }

                attestationVerifier = component "Attestation Verifier" {
                    description "Verifies platform TEE attestation during activation. Validates Apple App Attest certificate chains against the Apple CA, or Intel SGX quotes against IAS/DCAP. Called only at activation time."
                    technology "Go"
                    tags "Cloud" "Component"
                }

                licenseStore = component "License Store" {
                    description "Persistent store of license records: license_id mapped to HMAC(server_secret, device_public_key) and license status (active/deactivated). Never stores the raw device public key."
                    technology "Go, SQLite"
                    tags "Cloud" "Component" "Store"
                }
            }

            aiProxy = container "AI Proxy" {
                description "Stateless service that validates session tokens and forwards authenticated prompts to the AI Model API with the injected Gemini API key."
                technology "Go, HTTPS/TLS"
                tags "Cloud"

                # ──────────────────────────────────────────
                # Components inside AI Proxy
                # ──────────────────────────────────────────
                proxyHttpHandler = component "HTTP Handler" {
                    description "Single POST endpoint that receives the signed prompt and session token from the Prompt Pipeline over HTTPS/TLS. Delegates to the Token Validator before any forwarding occurs."
                    technology "Go, net/http"
                    tags "Cloud" "Component"
                }

                tokenValidator = component "Token Validator" {
                    description "Verifies the session token signature against the License Server public key loaded from env config at startup. Rejects expired tokens and invalid signatures. Fail closed — no fallback."
                    technology "Go"
                    tags "Cloud" "Component"
                }

                forwardingHandler = component "Forwarding Handler" {
                    description "Strips the session token, injects the AI provider API key into request headers, relays the request to the AI Model API, and streams the SSE response back to the Prompt Pipeline via io.Copy."
                    technology "Go"
                    tags "Cloud" "Component"
                }
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

        appleCA = softwareSystem "Apple Attestation CA" {
            description "Apple's certificate authority for App Attest. Used by the Attestation Verifier to validate that a device key pair was genuinely generated inside Apple Silicon Secure Enclave hardware."
            tags "External"
        }

        intelIAS = softwareSystem "Intel IAS / DCAP" {
            description "Intel's Attestation Service (IAS) or Data Center Attestation Primitives (DCAP). Used by the Attestation Verifier to validate SGX quotes against Intel's hardware root of trust."
            tags "External"
        }

        # ──────────────────────────────────────────
        # Relationships — User
        # ──────────────────────────────────────────
        user -> closeCode "Enters natural language prompts to edit code on" "Interactive TUI"
        user -> tui "Enters natural language prompts to edit code on" "Interactive TUI"
        user -> tuiRenderer "Types natural language prompt" "Interactive TUI"

        # ──────────────────────────────────────────
        # Relationships — CloseCode App components
        # ──────────────────────────────────────────
        tuiRenderer -> licenseManager "Triggers license init on startup and destroy on exit" "In-process"
        tuiRenderer -> promptPipeline "Forwards raw user prompt" "In-process"

        licenseManager -> teeModule "Calls tee_init / tee_sign / tee_destroy on" "C ABI via cgo"
        licenseManager -> httpHandler "Sends activation request and per-launch challenge-response to" "HTTPS/TLS"

        astEngine -> promptPipeline "Provides AST diff and code structure context to" "In-process"
        ragEngine -> promptPipeline "Provides top-k retrieved code snippets to" "In-process"
        promptPipeline -> licenseManager "Requests signed payload and session token from" "In-process"
        promptPipeline -> proxyHttpHandler "Dispatches signed prompt with session token to" "HTTPS/TLS"
        forwardingHandler -> promptPipeline "Streams LLM response to" "HTTPS/TLS (SSE)"

        teeModule -> teeAPIApple "Performs signing and attestation via in-process TEE Module" "Swift @_cdecl → CryptoKit"
        teeModule -> teeAPISGX "Performs signing and attestation via in-process TEE Module" "C ECALL → SGX SDK"

        # ──────────────────────────────────────────
        # Relationships — License Server components
        # ──────────────────────────────────────────
        httpHandler -> activationService "Routes /activate and /deactivate to" "In-process"
        httpHandler -> sessionService "Routes /challenge and /verify to" "In-process"

        activationService -> attestationVerifier "Requests TEE attestation verification from" "In-process"
        activationService -> licenseStore "Reads and writes license records to" "In-process"

        sessionService -> licenseStore "Reads device public key HMAC for signature verification from" "In-process"
        sessionService -> licenseManager "Issues signed session token to" "HTTPS/TLS"

        attestationVerifier -> appleCA "Validates App Attest certificate chain against" "HTTPS/TLS"
        attestationVerifier -> intelIAS "Validates SGX quote against" "HTTPS/TLS"

        # ──────────────────────────────────────────
        # Relationships — AI Proxy components
        # ──────────────────────────────────────────
        proxyHttpHandler -> tokenValidator "Forwards session token for validation to" "In-process"
        tokenValidator -> forwardingHandler "Passes validated request to" "In-process"
        forwardingHandler -> aiModelApi "Forwards prompt with injected AI provider API key to" "HTTPS/TLS"
        aiModelApi -> forwardingHandler "Streams LLM response to" "HTTPS/TLS (SSE)"

        # ──────────────────────────────────────────
        # Relationships — AI Proxy ↔ AI Provider (container level)
        # ──────────────────────────────────────────
        aiProxy -> aiModelApi "Forwards prompt with injected Gemini API key" "HTTPS/TLS"
        aiModelApi -> aiProxy "Streams LLM response" "HTTPS/TLS (SSE)"

        # ──────────────────────────────────────────
        # Deploy-time trust: License Server public key → Proxy config
        # ──────────────────────────────────────────
        # NOTE: This deploy-time relationship has no component-level equivalent.
        # The Session Service signs tokens with a static asymmetric key loaded
        # from server config at startup. The AI Proxy receives the corresponding
        # public key via environment config at deploy time — not via a runtime
        # call from any License Server component. It is intentionally modeled
        # only at the container level.
        licenseServer -> aiProxy "Provides public key for session token validation" "Deploy-time config"

    }

    views {

        systemContext closeCode "CloseCode-Context" {
            include user
            include closeCode
            include teeAPIApple
            include teeAPISGX
            include aiModelApi
            include appleCA
            include intelIAS
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
            include appleCA
            include intelIAS
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
            include appleCA
            include intelIAS
            description "C4 Level 3 — Component: Internal components of the CloseCode App. The License Manager is the sole owner of the TEE lifecycle and License Server handshake. AST and RAG Engines enrich prompts with code context before signing and dispatch."
            autolayout lr 50 100
        }

        component licenseServer "LicenseServer-Components" {
            include licenseManager
            include httpHandler
            include activationService
            include sessionService
            include attestationVerifier
            include licenseStore
            include appleCA
            include intelIAS
            description "C4 Level 3 — Component: Internal components of the License Server. The HTTP Handler routes activation and per-launch session flows to their respective services. The Attestation Verifier calls Apple or Intel CAs only at activation time. The Session Service owns nonce state in-process."
            autolayout lr 50 100
        }

        component aiProxy "AIProxy-Components" {
            include promptPipeline
            include proxyHttpHandler
            include tokenValidator
            include forwardingHandler
            include aiModelApi
            description "C4 Level 3 — Component: Internal components of the AI Proxy. The Token Validator enforces fail-closed session token verification before any forwarding occurs. The Forwarding Handler is the only component that holds the AI provider API key, injected at deploy time."
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
            element "Store" {
                shape Cylinder
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
