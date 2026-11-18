#!/usr/bin/env bash
# Read-only checks before deploying AgentPermit:
#  1. simulate the CREATE against live BSC mainnet state (eth_call to zero address)
#  2. compute the deterministic deployed address from the deployer nonce
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd /home/noodleo/agent-permit

RPC="https://bsc-rpc.publicnode.com"
FROM="0x1C73877184F0071781E94F17b2d10704022a85BA"
ZERO="0x0000000000000000000000000000000000000000"
INIT=$(python3 -c "import json;print(json.load(open('deploy-initcode.json'))['initCode'])")

echo "--- nonce of deployer"
NONCE=$(cast nonce "$FROM" --rpc-url "$RPC")
echo "nonce=$NONCE"

echo "--- eth_call simulate CREATE (zero address + initcode)"
# cast call with --create sends the tx as a contract creation simulation
cast call "$ZERO" --data "$INIT" --create --rpc-url "$RPC" 2>&1 | head -c 400 || true
echo

echo "--- expected deployed address (CREATE(from, nonce))"
python3 - <<PY
try:
    from Crypto.Hash import keccak
except Exception:
    keccak = None
import subprocess
print("(computed with cast below)")
PY
cast compute-address --create "$FROM" --nonce "$NONCE" --rpc-url "$RPC" 2>&1 | head -3 || true

echo "--- deployed runtime bytecode length (expected 23532 hex chars)"
python3 -c "
import json
a=json.load(open('out/AgentPermit.sol/AgentPermit.json'))
print('runtime len:', len(a['deployedBytecode']['object']))
"
