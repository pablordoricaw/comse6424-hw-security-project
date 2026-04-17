# ADR-0002: Require Always-Online Connectivity and Enforce Fail Closed

**Date:** 2026-04-16  
**Status:** Accepted  
**Deciders:** Null and Void

---

## Context

A common vulnerability in license server designs is the **grace period** or **offline mode**: when
the client cannot reach the license server, it falls back to a locally cached license state. This
creates a well-known attack vector where an attacker blocks the client's network access (via a
firewall rule, hosts file manipulation, or simply disabling the network interface), forcing the
client into offline mode to bypass license validation.

The project rubric asks the team to justify design trade-offs between security, performance,
complexity, and deployability.

## Decision

CloseCode will require active internet connectivity at all times and will **Fail Closed**: if the
license server is unreachable, or if the license token is invalid or expired, the application
will refuse to execute. No offline grace period will be implemented.

This decision is naturally justified by the application's architecture (see ADR-0001): CloseCode
requires a cloud LLM to function. If the client has no internet access, the application is useless
regardless of license status. The always-online requirement therefore adds zero marginal deployability
cost for legitimate users while completely eliminating the offline bypass attack vector.

## Alternatives Considered

- **Offline grace period (e.g., 7 days):** Introduces a vulnerability window where an attacker can
  operate indefinitely by repeatedly blocking network access before the grace period expires.
- **Cryptographically signed offline tokens with expiry:** Stronger than a simple grace period,
  but adds significant complexity (token revocation, clock skew attacks) without benefit for
  CloseCode since the cloud LLM dependency already mandates connectivity.

## Consequences

- **Security:** Eliminates the offline bypass attack surface entirely.
- **Performance:** License validation adds one network round-trip at startup; acceptable latency.
- **Deployability:** Legitimate users with reliable internet connectivity are unaffected.
  Users in air-gapped or restricted network environments cannot use the software; this is
  accepted as a known limitation.
- **Availability:** If the license server goes down, all clients are locked out. The team must
  design the license server for high availability, which is out of scope for this project but
  noted as a production deployment concern.
