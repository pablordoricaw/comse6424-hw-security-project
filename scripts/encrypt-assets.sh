#!/usr/bin/env bash
# scripts/encrypt-assets.sh
#
# Builds, signs, and encrypts the AST and RAG dylibs into .bundle files
# ready to be committed into Sources/CloseCode/Resources/.
#
# Usage: ./scripts/encrypt-assets.sh <path/to/master_aes.key> <codesign-identity>
# Example:
#   ./scripts/encrypt-assets.sh master_aes.key "Developer ID Application: Your Name (TEAMID)"

set -euo pipefail

MASTER_KEY_FILE="${1:?Usage: $0 <path/to/master_aes.key> <codesign-identity>}"
CODESIGN_IDENTITY="${2:?Usage: $0 <path/to/master_aes.key> <codesign-identity>}"

ASSETS_DIR="assets"
RESOURCES_DIR="Sources/CloseCode/Resources"

mkdir -p "$RESOURCES_DIR"

# ── Build ────────────────────────────────────────────────────────────────────

echo "▶ Building dylibs..."
swiftc -emit-library "$ASSETS_DIR/ast_engine.swift" -o "$ASSETS_DIR/ast.dylib"
swiftc -emit-library "$ASSETS_DIR/rag_engine.swift" -o "$ASSETS_DIR/rag.dylib"

# ── Sign ─────────────────────────────────────────────────────────────────────

echo "▶ Signing dylibs..."
codesign --sign "$CODESIGN_IDENTITY" --force --timestamp=none "$ASSETS_DIR/ast.dylib"
codesign --sign "$CODESIGN_IDENTITY" --force --timestamp=none "$ASSETS_DIR/rag.dylib"

# ── Encrypt ──────────────────────────────────────────────────────────────────
# Output format: 12-byte random nonce || AES-GCM ciphertext+tag
# This matches exactly what CryptoKit's AES.GCM.SealedBox(combined:) expects.

KEY_HEX=$(xxd -p -c 256 "$MASTER_KEY_FILE" | tr -d '\n')

encrypt_asset() {
  local input="$1"
  local output="$2"
  local name
  name=$(basename "$input")

  python3 - "$input" "$output" "$MASTER_KEY_FILE" <<'EOF'
import sys
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import os

input_path, output_path, key_path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(key_path, 'rb') as f:
    key = f.read()

with open(input_path, 'rb') as f:
    plaintext = f.read()

nonce = os.urandom(12)
aesgcm = AESGCM(key)
ciphertext = aesgcm.encrypt(nonce, plaintext, None)  # nonce || ciphertext || tag (tag appended by library)

# Output format: 12-byte nonce || ciphertext+tag
# Matches exactly what CryptoKit AES.GCM.SealedBox(combined:) expects
with open(output_path, 'wb') as f:
    f.write(nonce + ciphertext)

EOF

  echo "  ✓ $name → $output"
}

echo "▶ Encrypting..."
encrypt_asset "$ASSETS_DIR/ast.dylib" "$RESOURCES_DIR/ast.bundle"
encrypt_asset "$ASSETS_DIR/rag.dylib" "$RESOURCES_DIR/rag.bundle"

echo "✓ Done. Commit Sources/CloseCode/Resources/ast.bundle and rag.bundle."
