#!/bin/bash
# Try a contract CREATION through baw without --to (the CLI calls it required for EVM,
# but the backend may still build a creation tx when the field is absent).
set -u
export PATH="$HOME/.hermes/tools/node-26.12.1-linux-x64/bin:$PATH"
export NODE_OPTIONS="--require $HOME/.config/dnspin/pin_dns.cjs"
cd /home/noodleo/agent-permit

FROM="0x1C73877184F0071781E94F17b2d10704022a85BA"
INIT=$(python3 -c "import json;print(json.load(open('deploy-initcode.json'))['initCode'])")

echo "=== attempt 1: no --to at all"
baw contract-call preview \
  --binanceChainId 56 \
  --from "$FROM" \
  --value 0 \
  --inputData "$INIT" \
  --gasLimit 3000000 \
  --json 2>&1 | head -c 1200
echo
