#!/usr/bin/env bash
# Create a throwaway deployer keypair. The private key never leaves this file.
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd /home/noodleo/agent-permit

if [ ! -f deployer.json ]; then
  cast wallet new --json > deployer.json
  chmod 600 deployer.json
  echo "created deployer.json (mode 600)"
else
  echo "deployer.json already exists"
fi

ADDR=$(python3 -c "import json;print(json.load(open('deployer.json'))['address'])")
echo "deployer address: $ADDR"
echo "deployer balance:"
cast balance "$ADDR" --rpc-url https://bsc-rpc.publicnode.com
