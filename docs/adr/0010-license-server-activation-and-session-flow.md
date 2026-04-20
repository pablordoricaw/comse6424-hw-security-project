# ADR-0010: License Server Activation and Session Flow

**Date:** 2026-04-20
**Status:** Accepted
**Deciders:** Null and Void

---

## Context

ADR-0007 defines the cryptographic protocols for device activation and per-launch
challenge-response verification. This ADR documents the License Server's internal
architectural decisions that implement those protocols: how responsibilities are
partitioned across components, how state is managed, and what persistence technology
is used.

The License Server has two distinct operational modes with very different
characteristics:

- **Activation** — rare, heavyweight, irreversible per device. Involves TEE attestation
  verification against an external CA, license record creation, and device binding.
  Happens once at first install and again only if the user wipes their TEE or
  re-activates on a new machine.
- **Per-launch session** — frequent, latency-sensitive, stateful only for the duration
  of a nonce TTL (~90 seconds). Involves issuing a nonce, verifying a TEE-signed
  challenge, and returning a short-lived session token.

These two modes have different failure modes, different external dependencies, and
different performance requirements. Conflating them in a single component would make
each harder to reason about, test, and audit independently.

## Decision

### Two-Service Split: Activation Service and Session Service

The License Server's business logic is split into two independent components:

**Activation Service** owns:
- First-time device binding (`/activate`): validates `license_id`, invokes the
  Attestation Verifier, stores `HMAC(server_secret, device_public_key)` and
  license status in the License Store
- Deactivation (`/deactivate`): marks the license record as revoked in the
  License Store. Deactivation is owned by the Activation Service (not a separate
  component) because deactivation is the logical inverse of activation — both
  operate on the license record's lifecycle state

**Session Service** owns:
- Nonce issuance (`/challenge`): generates a cryptographically random 32-byte
  nonce and stores it in an in-process TTL map with a ~90-second expiry
- Challenge verification and token issuance (`/verify`): reads the stored
  `HMAC(server_secret, device_public_key)` from the License Store, verifies
  the TEE-signed challenge, and returns a short-lived signed session token
  (TTL: 1 hour)
- Anti-replay enforcement: nonces are consumed atomically on use (read-then-delete)
  and rejected if expired

A single **HTTP Handler** component routes incoming requests to the appropriate
service based on path (`/activate`, `/deactivate` → Activation Service;
`/challenge`, `/verify` → Session Service).

### Nonce State: In-Process TTL Map

Nonces are stored in an in-process TTL map (e.g., `go-cache` or a
`sync.Map` with a background sweep) owned by the Session Service. They are
not persisted to disk or to an external store such as Redis.

This is correct because:
- The License Server is a single-instance service — there is no horizontal
  scaling scenario where a nonce issued by instance A must be verifiable by
  instance B
- Nonces issued before a server restart are inherently expired — there is no
  need to recover nonce state across restarts
- In-process storage avoids adding Redis or Memcached as an infrastructure
  dependency for a single-instance course project deployment
- The atomicity requirement (read-then-delete must not race) is satisfied
  by a mutex-protected map, which is simpler and more auditable than
  a Redis `SET`/`DEL` pair

### Persistence: SQLite via the License Store

License records are persisted in a SQLite database owned exclusively by the
License Store component. The schema is minimal:

```sql
CREATE TABLE licenses (
    license_id      TEXT PRIMARY KEY,
    pubkey_hmac     TEXT NOT NULL,   -- HMAC(server_secret, device_public_key)
    status          TEXT NOT NULL,   -- 'active' | 'revoked'
    activated_at    INTEGER NOT NULL,
    revoked_at      INTEGER
);
```

SQLite is chosen over Postgres or MySQL because:
- The License Server is a single-instance service with no concurrent writers
  beyond the single Go process — SQLite's write serialisation is not a
  bottleneck
- SQLite requires no separate database server process, no connection pool
  configuration, and no separate infrastructure to deploy or monitor
- The database file is small (one row per activated device) and easily
  backed up as a flat file
- Adding Postgres for a single-instance course project deployment would
  add operational complexity with no security or performance benefit

The License Store component is the only component that reads from or writes
to the SQLite file. Neither the Session Service nor the Activation Service
access the database directly — all reads and writes go through the License
Store's interface.

### What Is Never Stored

Consistent with ADR-0007, the License Store never stores:
- The raw device public key (only `HMAC(server_secret, device_public_key)`)
- The server signing key (loaded from environment config at startup, never
  written to disk)
- Nonces (in-process only, never persisted)

A full database breach exposes license IDs and HMAC digests. Without the
`server_secret`, the HMAC digests cannot be reversed to recover device
public keys and cannot be used to forge valid challenge-response signatures.

## Alternatives Considered

- **Single monolithic License Service (no split):** Simpler to deploy but
  conflates two components with different failure modes, different external
  dependencies (Activation depends on external CAs; Session does not), and
  different performance requirements. A bug in activation logic could affect
  session token issuance for running clients. Rejected in favour of the
  two-service split.
- **Redis for nonce storage:** Correct for a horizontally-scaled deployment
  but unnecessary for a single-instance server. Adds an infrastructure
  dependency (Redis process, connection management, failure handling) with
  no benefit in this deployment topology. Rejected.
- **Postgres for the License Store:** Operationally heavier than SQLite with
  no benefit for single-instance, low-write workloads. Rejected.
- **Deactivation as a separate component:** Deactivation is the logical
  inverse of activation and operates on the same license record lifecycle
  state. Splitting it out would require it to duplicate the Activation
  Service's License Store access pattern with no architectural benefit.
  Rejected.

## Consequences

- **Security:** The License Store never holds raw key material. The nonce
  store's in-process TTL map prevents replay attacks without external
  infrastructure. The two-service split limits the blast radius of a bug
  in either service.
- **Auditability:** A security auditor reviewing the per-launch verification
  flow inspects only the Session Service and License Store. The Activation
  Service and Attestation Verifier are out of scope for per-launch audits.
- **Operational simplicity:** A single Go binary, a single SQLite file, and
  no external state dependencies beyond the attestation CAs. The server can
  be deployed as a single container with a mounted volume for the SQLite file.
- **Scalability ceiling:** The single-instance assumption is baked into the
  nonce storage design. Horizontal scaling would require migrating nonce
  storage to Redis and switching the License Store to Postgres. This is an
  acceptable trade-off for the course project scope.
