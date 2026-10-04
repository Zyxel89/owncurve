#!/usr/bin/env bash
# Compara el programa desplegado con el binario compilado aquí.
#   bash scripts/verify.sh [RPC_URL]
set -euo pipefail
RPC="${1:-${RPC_URL:-https://api.devnet.solana.com}}"
PID=$(jq -r .address target/idl/owncurve.json)
LOCAL=target/deploy/owncurve.so
[ -f "$LOCAL" ] || { echo "Build first: anchor build --skip-lint --tools-version v1.52 --arch v0"; exit 1; }
TMP=$(mktemp)
solana program dump "$PID" "$TMP" --url "$RPC" >/dev/null
N=$(stat -c %s "$LOCAL")
ONCHAIN=$(head -c "$N" "$TMP" | sha256sum | awk '{print $1}')
BUILT=$(sha256sum "$LOCAL" | awk '{print $1}')
# el resto de la cuenta debe ser relleno de ceros
TAIL=$(tail -c +$((N + 1)) "$TMP" | tr -d '\0' | wc -c)
rm -f "$TMP"
echo "program  $PID"
echo "on-chain $ONCHAIN"
echo "local    $BUILT"
if [ "$ONCHAIN" = "$BUILT" ] && [ "$TAIL" = 0 ]; then echo "MATCH: the deployed program is this source code"; else echo "MISMATCH"; exit 1; fi
