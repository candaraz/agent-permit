#!/bin/bash
# Preview the AgentPermit deploy from the Binance Agentic Wallet (read-only).
set -u
export PATH="$HOME/.hermes/tools/node-26.12.1-linux-x64/bin:$PATH"
export NODE_OPTIONS="--require $HOME/.config/dnspin/pin_dns.cjs"
cd /home/noodleo/agent-permit

FROM="0x1C73877184F0071781E94F17b2d10704022a85BA"
INIT=$(python3 -c "import json;print(json.load(open('deploy-initcode.json'))['initCode'])")

# contract creation: no --to, value 0
baw contract-call preview \
  --binanceChainId 56 \
  --from "$FROM" \
  --to "$FROM" \
  --value 0 \
  --inputData "$INIT" \
  --gasLimit 1500000 \
  --json
