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

        # ──────────────────────────────────────────
        # Relationships — App ↔ TEE platform APIs
        # (TEE Module is an in-process component; its
        #  external calls surface here at container level)
        # ──────────────────────────────────────────
        tui -> teeAPIApple "Performs signing and attestation via in-process TEE Module" "Swift @_cdecl → CryptoKit"
        tui -> teeAPISGX "Performs signing and attestation via in-process TEE Module" "C ECALL → SGX SDK"

        # ──────────────────────────────────────────
        # Relationships — App (local) ↔ Cloud
        # ──────────────────────────────────────────
        tui -> licenseServer "Sends TEE attestation and signed challenge for license verification" "HTTPS/TLS"
        licenseServer -> tui "Returns signed session token" "HTTPS/TLS"
        tui -> aiProxy "Sends prompt with session token" "HTTPS/TLS"
        aiProxy -> tui "Streams LLM response" "HTTPS/TLS (SSE)"

        # ──────────────────────────────────────────
        # Relationships — AI Proxy ↔ AI Provider
        # ──────────────────────────────────────────
        aiProxy -> aiModelApi "Forwards prompt with injected Gemini API key" "HTTPS/TLS"
        aiModelApi -> aiProxy "Streams LLM response" "HTTPS/TLS (SSE)"

        # ──────────────────────────────────────────
        # Deploy-time trust: License Server public key → Proxy config
        # ──────────────────────────────────────────
        licenseServer -> aiProxy "Provides public key for session token validation" "Deploy-time config"

        # ──────────────────────────────────────────
        # Context-level relationships (system → external TEE platforms)
        # ──────────────────────────────────────────
        closeCode -> teeAPIApple "Performs signing and attestation via (Apple Silicon)" "CryptoKit / Secure Enclave"
        closeCode -> teeAPISGX "Performs signing and attestation via (Intel)" "SGX SDK / ECALL"

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
