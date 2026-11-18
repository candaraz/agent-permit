#!/bin/bash
# Preview contract CREATION via the Binance Agentic Wallet.
# A transaction to an account with no code and non-empty data is CREATE by EVM
# rules, so --to is the zero address.
set -u
export PATH="$HOME/.hermes/tools/node-26.12.1-linux-x64/bin:$PATH"
export NODE_OPTIONS="--require $HOME/.config/dnspin/pin_dns.cjs"
cd /home/noodleo/agent-permit

FROM="0x1C73877184F0071781E94F17b2d10704022a85BA"
ZERO="0x0000000000000000000000000000000000000000"
INIT=$(python3 -c "import json;print(json.load(open('deploy-initcode.json'))['initCode'])")

baw contract-call preview \
  --binanceChainId 56 \
  --from "$FROM" \
  --to "$ZERO" \
  --value 0 \
  --inputData "$INIT" \
  --gasLimit 3000000 \
  --json
