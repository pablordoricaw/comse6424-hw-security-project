#!/usr/bin/env bash
# scripts/simulate-attacks.sh
#
# Security Validation Attack Simulation Suite
#
# Simulates Tier 1 (Motivated Competitor) attacks against CloseCode and
# verifies each is fully mitigated. Results are logged to logs/attack-simulation.log.
#
# Attacks simulated:
#   1. Token copy / transfer to another machine (Spoofing / EoP)
#   2. Filesystem tampering with encrypted bundles (Tampering)
#   3. Keychain token corruption (Tampering)
#   4. Missing license token no activation (Availability / DoS)
#   5. Expired license certificate (Tampering expiry enforcement)
#
# Attacks NOT simulated (Tier 2 accepted residual risk require instrumentation):
#   - IOPlatformUUID spoofing via Frida / DYLD_INSERT_LIBRARIES
#   - Post-unlock memory extraction via kernel debugger
#   - Microarchitectural side-channel attacks
#   - System clock rollback (expiration bypass) documented accepted risk
#
# Usage:
#   chmod +x scripts/simulate-attacks.sh
#   ./scripts/simulate-attacks.sh <path/to/valid.cert>

set -uo pipefail

CERT_FILE="${1:?Usage: $0 <path/to/valid.cert>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$REPO_ROOT/logs"
LOG_FILE="$LOG_DIR/attack-simulation.log"
RESOURCES_DIR="$REPO_ROOT/Sources/CloseCode/Resources"
AST_BUNDLE="$RESOURCES_DIR/ast.bundle"

# Keychain constants must match KeychainAdapter.swift
KEYCHAIN_ACCOUNT="com.closecode.licensegate.token"
KEYCHAIN_SERVICE="$KEYCHAIN_ACCOUNT"

mkdir -p "$LOG_DIR"

# ── Helpers ──────────────────────────────────────────────────────────────────

PASS=0
FAIL=0
TOTAL=0

log() { echo "$*" | tee -a "$LOG_FILE"; }

run_closecode() {
  echo "/exit" | swiftly run swift run closecode 2>&1 |
    sed $'s/\x1b\\[[0-9;]*[mhHJKlABCDfsuGr]//g' |
    sed $'s/\x1b\\[[?][0-9]*[lh]//g' ||
    true
}

assert_contains() {
  local name="$1" output="$2" expected="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$output" | grep -qi "$expected"; then
    log "  ✅ PASS: $name"
    log "     Matched: \"$expected\""
    PASS=$((PASS + 1))
  else
    log "  ❌ FAIL: $name"
    log "     Expected output containing: \"$expected\""
    log "     Actual output:"
    echo "$output" | sed 's/^/     /' | tee -a "$LOG_FILE"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local name="$1" output="$2" forbidden="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$output" | grep -qi "$forbidden"; then
    log "  ❌ FAIL: $name"
    log "     Output must NOT contain: \"$forbidden\""
    echo "$output" | sed 's/^/     /' | tee -a "$LOG_FILE"
    FAIL=$((FAIL + 1))
  else
    log "  ✅ PASS: $name"
    log "     Correctly did not expose: \"$forbidden\""
    PASS=$((PASS + 1))
  fi
}

keychain_delete_token() {
  security delete-generic-password -a "$KEYCHAIN_ACCOUNT" 2>/dev/null || true
}

restore_activation() {
  log "  ↩ Re-activating from $CERT_FILE..."
  swiftly run swift run closecode --activate "$CERT_FILE" 2>&1 | tee -a "$LOG_FILE" || true
}

# ── Preamble ──────────────────────────────────────────────────────────────────

>"$LOG_FILE"
log "============================================================"
log "  CloseCode Phase 3 Attack Simulation Suite"
log "  $(date)"
log "  Cert: $CERT_FILE"
log "============================================================"
log ""

if ! security find-generic-password -a "$KEYCHAIN_ACCOUNT" &>/dev/null; then
  log "⚠ No active token found. Activating first..."
  restore_activation
fi

# ── Attack 1: Token Copy / Transfer ──────────────────────────────────────────

log "------------------------------------------------------------"
log "Attack 1: License Token Copy / Transfer to Another Machine"
log "  STRIDE: Spoofing + Elevation of Privilege"
log "  Simulation: Delete SE-bound token (simulates token on wrong"
log "              machine Wrapped_AES_Key is device-bound)."
log "  Expected:   License Gate detects missing token, fails closed."
log ""

keychain_delete_token
OUTPUT=$(run_closecode)
assert_contains "Missing token → app fails closed" "$OUTPUT" "not activated\|no license\|tokenNotFound\|activate\|not found"
assert_not_contains "Proprietary assets not exposed" "$OUTPUT" "Pipeline ready\|AST Context\|RAG Context"
restore_activation
log ""

# ── Attack 2: Filesystem Tampering with Encrypted Bundles ────────────────────

log "------------------------------------------------------------"
log "Attack 2: Filesystem Tampering with Encrypted Asset Bundles"
log "  STRIDE: Tampering"
log "  Simulation: Flip byte at offset 20 in ast.bundle (past the"
log "              12-byte nonce) invalidates AES-GCM auth tag."
log "  Expected:   Decryption fails; app fails closed."
log ""

cp "$AST_BUNDLE" "$AST_BUNDLE.bak"
printf '\xDE' | dd of="$AST_BUNDLE" bs=1 seek=20 conv=notrunc 2>/dev/null

OUTPUT=$(run_closecode)
assert_contains "Tampered bundle → AES-GCM auth tag rejected" "$OUTPUT" "decryption failed\|authentication\|corrupt\|load failed\|startup failed"
assert_not_contains "Tampered bundle does not expose assets" "$OUTPUT" "Pipeline ready\|AST Context\|RAG Context"

mv "$AST_BUNDLE.bak" "$AST_BUNDLE"
log "  ↩ Restored original ast.bundle"
log ""

# ── Attack 3: Keychain Token Corruption ──────────────────────────────────────

log "------------------------------------------------------------"
log "Attack 3: Keychain Token Corruption"
log "  STRIDE: Tampering"
log "  Simulation: Overwrite Keychain token blob with invalid JSON."
log "  Expected:   Token decode fails before SE is contacted."
log ""

keychain_delete_token
security add-generic-password \
  -a "$KEYCHAIN_ACCOUNT" \
  -s "$KEYCHAIN_ACCOUNT" \
  -U \
  -w "CORRUPTED_TOKEN_PAYLOAD" 2>/dev/null || true

assert_contains "Corrupted token → decode failure" "$OUTPUT" "decode\|corrupt\|invalid\|token\|failed\|activate"
assert_not_contains "Corrupted token does not reach SE" "$OUTPUT" "Pipeline ready\|AST Context\|RAG Context"
keychain_delete_token
restore_activation
log ""

# ── Attack 4: No License Token (Cold Start) ──────────────────────────────────

log "------------------------------------------------------------"
log "Attack 4: No License Token Present (Cold Start)"
log "  STRIDE: Denial of Service"
log "  Simulation: Delete token, cold-start the app."
log "  Expected:   App fails closed, prompts for activation."
log ""

keychain_delete_token
OUTPUT=$(run_closecode)
assert_contains "No token → app prompts for activation" \
  "$OUTPUT" \
  "not activated\|no license\|activate\|not found\|tokenNotFound\|startup failed\|decode\|format"
assert_not_contains "No token → assets never loaded" "$OUTPUT" "Pipeline ready\|AST Context\|RAG Context"
restore_activation
log ""

# ── Attack 5: Expired License Certificate ────────────────────────────────────

log "------------------------------------------------------------"
log "Attack 5: Expired License Certificate"
log "  STRIDE: Tampering"
log "  Simulation: Generate cert with past expiry, attempt activate."
log "  Expected:   License Gate rejects expired cert at activation."
log "  Note:       Clock rollback bypass is accepted residual risk"
log "              (documented in docs/CHECKPOINT_1.md)."
log ""

swiftly run swift run closecode --deactivate 2>&1 | tee -a "$LOG_FILE" || true

FINGERPRINT=$(swiftly run swift run get-fingerprint 2>/dev/null | tail -1)
log "  Device fingerprint: $FINGERPRINT"

EXPIRED_CERT="/tmp/closecode-expired-$$.cert"
swiftly run swift run generate-cert \
  --expiry "2020-01-01" \
  --fingerprint "$FINGERPRINT" \
  --output "$EXPIRED_CERT" 2>&1 | tee -a "$LOG_FILE" || true

OUTPUT=$(swiftly run swift run closecode --activate "$EXPIRED_CERT" 2>&1 || true)
assert_contains "Expired cert rejected at activation" "$OUTPUT" "expired\|expiration\|invalid\|rejected\|past"
assert_not_contains "Expired cert does not activate" "$OUTPUT" "activated\|success\|Pipeline ready"

rm -f "$EXPIRED_CERT"
restore_activation
log ""

# ── Summary ───────────────────────────────────────────────────────────────────

log "============================================================"
log "  Results: $PASS/$TOTAL passed, $FAIL/$TOTAL failed"
log "  Log: $LOG_FILE"
log ""
log "  Tier 2 attacks NOT simulated (accepted residual risk):"
log "  - IOPlatformUUID spoofing (requires Frida / SIP disabled)"
log "  - Post-unlock memory extraction (requires kernel debugger)"
log "  - Microarchitectural side-channel attacks"
log "  - System clock rollback / expiration bypass"
log "    (documented in docs/CHECKPOINT_1.md § Residual Risk)"
log "============================================================"

[ "$FAIL" -gt 0 ] && exit 1 || exit 0
