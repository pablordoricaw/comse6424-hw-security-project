# ADR-0009: AI Proxy as Authenticated Forwarding Layer

**Date:** 2026-04-19  
**Status:** Accepted  
**Deciders:** Null and Void

---

## Context

CloseCode's Fail Closed enforcement (ADR-0002) requires that the AI Model API only responds
to requests from licensed CloseCode executions. The AI provider's API (e.g., OpenAI, Anthropic,
Google) natively authenticates requests using its own API keys — it has no mechanism to validate
a CloseCode-issued session token or TEE attestation.

Three approaches were considered to bridge CloseCode's license verification with the AI
provider's authentication:

1. **Shared permanent API key:** License Server distributes the real AI provider API key to
   the App at license validation time. The App includes it in every prompt request directly.
2. **Short-lived provider API key:** License Server uses provider key-scoping/rotation features
   (e.g., OpenAI's API) to mint a short-lived AI provider key per session and return it to
   the App instead of the real key.
3. **CloseCode-controlled AI proxy:** A separate stateless service sits between the App and
   the AI provider. It validates CloseCode session tokens and injects the real AI provider
   API key into forwarded requests. The real key never leaves CloseCode-controlled
   infrastructure.

## Decision

We will deploy a **CloseCode-controlled AI proxy** as a separate stateless service.

The proxy's responsibilities are strictly limited to:
1. Validating the CloseCode session token (signed by the License Server's private key,
   verified using the License Server's public key baked into the proxy config at deploy time)
2. Stripping the CloseCode session token from the request
3. Injecting the real AI provider API key into the forwarded request headers
4. Relaying the request and streaming response between the App and the AI provider

The proxy does **not** parse, log, or store prompt content. It is a thin authenticated
forwarding layer, not an AI gateway or content filter.

### Secrets Management

The proxy requires two secrets at startup, both injected as environment variables by the
deployment system (never stored in code or on disk):

- `LICENSE_SERVER_PUBLIC_KEY` — used to verify CloseCode session token signatures
- `AI_PROVIDER_API_KEY` — the real AI provider API key, injected into forwarded requests

In production, both secrets are stored in a secrets manager (e.g., GCP Secret Manager)
and injected at container startup. Neither the License Server nor the App ever holds or
sees the AI provider API key.

### Streaming

The proxy must relay server-sent event (SSE) streaming responses from the AI provider back
to the App in real time. Buffering the full response before forwarding is not acceptable as
it degrades the TUI user experience. The proxy uses `io.Copy` to stream response chunks
directly, keeping it stateless with respect to prompt content.

### Provider Scope

For the initial implementation, the proxy is hardcoded to a single AI provider (OpenAI).
This eliminates the need for a provider translation layer and keeps the proxy implementation
to approximately 40-60 lines of Go. Supporting additional providers would require a
per-provider request/response adapter but does not change the proxy's core architecture.

## Alternatives Considered

- **Shared permanent API key:** The real API key is distributed to the App at license
  validation time and held in App memory for the session. A root-level memory dump attack
  extracts the key permanently — an attacker needs a valid license only once to obtain a
  key that works indefinitely. Directly undermines the Fail Closed guarantee. Rejected.
- **Short-lived provider API key:** The License Server mints a short-lived OpenAI scoped
  key per session and returns it to the App. The App holds a live OpenAI key in memory for
  up to 1 hour. A memory dump attack yields up to 1 hour of unauthorized AI access per
  extraction, and the attacker can automate re-extraction. Better than a permanent key but
  still places AI provider credentials in App memory. Rejected in favor of the proxy which
  keeps credentials entirely out of the App.
- **Co-located proxy and License Server:** Running the proxy and License Server as a single
  service simplifies deployment but couples two failure domains — a License Server outage
  takes down AI access, and vice versa. The proxy is stateless and independently scalable;
  the License Server holds persistent license state. Separating them follows the single
  responsibility principle. Rejected.

## Consequences

- **Security:** The real AI provider API key never leaves CloseCode-controlled server
  infrastructure. The App holds only a short-lived CloseCode session token. A memory dump
  of the App yields a token that expires within 1 hour and cannot be renewed without a
  valid TEE. Residual risk: a memory dump of the *proxy* process would yield the real API
  key — proxy host security is a deployment concern documented in `THREAT_MODEL.md`.
- **Failure domains:** License Server and Proxy fail independently. A License Server outage
  prevents new session token issuance (new launches fail) but does not affect in-progress
  sessions whose tokens have not yet expired. A Proxy outage prevents prompt forwarding but
  does not affect license validation.
- **Complexity:** A third deployed service (in addition to License Server and AI provider)
  is required. The proxy is stateless and requires no database, making it operationally
  simple to deploy and scale.
- **Streaming:** The proxy must handle SSE streaming relay. This is the primary
  implementation complexity of the proxy service.
- **Course project shortcut:** In the course project implementation, secrets are loaded
  from a `.env` file excluded from the repository via `.gitignore`. In production this
  would be replaced by a secrets manager injection at container startup. This is an
  implementation shortcut, not an architectural deviation.
- **Provider lock-in:** The proxy is initially hardcoded to OpenAI. Switching providers
  requires updating the proxy's forwarding logic but does not affect the App, License
  Server, or session token design.
