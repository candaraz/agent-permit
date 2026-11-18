#!/usr/bin/env bash
# Empirically determine the CREATE2 proxy calldata layout on BSC.
set -u
export PATH="$HOME/.foundry/bin:$PATH"
export ETH_RPC_URL=https://bsc-rpc.publicnode.com
cd /home/noodleo/agent-permit

PROXY=0x4e59b44847b379578588920cA78FbF26c0B4956C
INIT=$(python3 -c "import json;print(json.load(open('deploy-calldata.json'))['initCode'][2:])")
SALT=$(python3 -c "import json;print(json.load(open('deploy-calldata.json'))['salt'][2:])")

echo "=== A: initcode ++ salt"
cast call "$PROXY" "0x${INIT}${SALT}" 2>&1 | head -c 300
echo
echo "=== B: salt ++ initcode"
cast call "$PROXY" "0x${SALT}${INIT}" 2>&1 | head -c 300
echo
echo "=== C: initcode ++ zero salt"
cast call "$PROXY" "0x${INIT}$(printf '0%.0s' {1..64})" 2>&1 | head -c 300
echo
echo "=== D: trace of A (first 25 lines)"
cast call "$PROXY" "0x${INIT}${SALT}" --trace 2>&1 | head -25
