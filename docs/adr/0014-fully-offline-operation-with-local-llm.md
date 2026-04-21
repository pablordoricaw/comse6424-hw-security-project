# ADR-0014: Fully Offline Operation with Local LLM

## Status

Accepted

**Supersedes:** [ADR-0002 Always Online Fail Closed](./0002-always-online-fail-closed.md), [ADR-0009 AI Proxy as Authenticated Forwarding Layer](./0009-ai-proxy-as-authenticated-forwarding-layer.md), [ADR-0013 Go as License Server and AI Proxy Language](./0013-go-as-license-server-and-ai-proxy-language.md)

## Context

The original CloseCode architecture required three networked components: a CloseCode App, a License Server, and an AI Proxy. The License Server was responsible for device binding via remote attestation, challenge-response nonce issuance, and signed session token issuance. The AI Proxy was responsible for token validation before forwarding prompts to a remote model provider API, and for keeping the provider API key off the client entirely.

This architecture was always-online and fail-closed: if the License Server or AI Proxy were unreachable, the application refused to run. ADR-0002 explicitly accepted this availability risk as a deliberate security trade-off — offline operation was considered a stronger license-bypass path than the availability risk it removed.

The project requirement has changed. CloseCode must now operate in a **fully offline** manner with no network dependency at runtime. This eliminates the License Server and AI Proxy as components.

## Decision

Remove the License Server and AI Proxy entirely. CloseCode becomes a single self-contained application with no runtime network dependency.

LLM inference is served by a **local model running on-device** (e.g. via Ollama or a directly embedded inference runtime). Prompts are sent to the local model and responses are streamed back within the same machine. No prompt content leaves the device.

Licensing operates fully offline. Device binding and license verification are handled entirely within the application using the on-device Secure Enclave. The mechanism for this is specified in ADR-0016.

## Options Considered

### Option A — Retain License Server, drop AI Proxy only

Keep the License Server for device binding and attestation, but replace the remote model with a local LLM. This would preserve remote attestation and server-backed session tokens.

- ✅ Retains the strongest device binding mechanism (remote attestation)
- ✅ Retains server-enforced license reuse prevention
- ❌ Contradicts the fully offline requirement — the License Server is a network dependency
- ❌ Adds operational complexity (server must be deployed and reachable) for no permitted benefit

**Rejected** — violates the offline constraint.

### Option B — One-time online activation, then offline

Require network access only at first activation (to have the License Server sign the device binding), then operate fully offline thereafter using a server-signed license certificate.

- ✅ Retains server-signed device binding — stronger than purely local self-signed token
- ✅ Allows server-enforced activation limits
- ❌ Still requires a reachable License Server at activation time
- ❌ Contradicts the fully offline requirement as stated

**Rejected** — the requirement is fully offline with no server infrastructure.

### Option C — Fully offline, local LLM, local license enforcement (chosen)

Remove all server components. License enforcement is handled entirely on-device using the Secure Enclave. LLM inference is served locally.

- ✅ No network dependency at any point in the application lifecycle
- ✅ Eliminates the always-online single point of failure
- ✅ Eliminates the AI Proxy API key custody problem — there is no remote API key to protect
- ✅ Session tokens are no longer needed — no server to issue or validate them
- ❌ License reuse across machines cannot be prevented — no server to record or enforce activation limits
- ❌ Remote attestation is no longer possible — the License Server was the attestation verifier

**Chosen.**

## Consequences

### Eliminated threats

- **Remote API key theft** — there is no remote model provider API key. The local model is open-weight and requires no credential.
- **Session token replay** — session tokens no longer exist. There is nothing to replay.
- **License Server availability as a single point of failure** — the server is gone; availability is no longer a concern.

### New and shifted threats

- **License reuse across machines** — without a server to record activation bindings, two users sharing a `license_id` before activation each produce valid independent license tokens on their respective machines. This is accepted as residual risk and documented in the threat model.
- **No remote attestation** — the License Server was the external authority that verified Secure Enclave attestation. Without it, there is no external validator to confirm that the device key was generated inside real hardware. The consequences of this and the partial mitigations available are addressed in ADR-0016.
- **Local LLM prompt confidentiality** — prompts are processed entirely on-device. They do not leave the machine over the network. The confidentiality threat is limited to local memory inspection and microarchitectural side channels, which are addressed in the threat model.

### Superseded decisions

- **ADR-0002** (Always Online Fail Closed) — the premise is inverted. The system is now always offline.
- **ADR-0009** (AI Proxy as Authenticated Forwarding Layer) — the AI Proxy no longer exists.
- **ADR-0013** (Go as License Server and AI Proxy Language) — the License Server and AI Proxy no longer exist; Go is no longer required for those components.
