workspace "CloseCode" "C4 architecture model for CloseCode, a license-enforced AI coding agent immune to software and microarchitectural attacks." {

    model {

        user = person "User" {
            description "A vibe-coder who uses CloseCode to edit code via natural language prompts on their local machine."
        }

        closeCode = softwareSystem "CloseCode" {
            description "A node-locked, license-enforced AI coding agent. Requires Apple Silicon (Secure Enclave) or Intel SGX. Enforces that only licensed devices on supported hardware can reach the AI Model API."
            tags "Internal"
        }

        aiModelApi = softwareSystem "AI Model API" {
            description "A third-party Model-as-a-Service provider (Gemini). Accepts prompt requests forwarded by the CloseCode AI Proxy. Has no awareness of CloseCode license enforcement that is handled upstream."
            tags "External"
        }

        # Relationships
        user -> closeCode "Enters natural language prompts to edit code on" "Interactive TUI"
        closeCode -> aiModelApi "Forwards licensed prompt requests to and receives LLM responses from" "HTTPS/TLS"

    }

    views {

        systemContext closeCode "CloseCode-Context" {
            include user
            include closeCode
            include aiModelApi
            description "C4 Level 1 — System Context: CloseCode as a single system delivering value to the User, depending on the AI Model API for LLM inference."
            autolayout lr
        }

        styles {
            element "Person" {
                shape Person
                background "#2d8c4e"
                color "#ffffff"
                fontSize 20
            }
            element "Internal" {
                background "#1a5fa8"
                color "#ffffff"
                fontSize 19
            }
            element "External" {
                background "#4baed4"
                color "#ffffff"
                fontSize 19
            }
            relationship "Relationship" {
                fontSize 19
                color "#444444"
                style "Dashed"
            }
        }

    }

}
