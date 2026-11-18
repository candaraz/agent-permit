#!/bin/bash
# Is the baw simulation failure specific to OUR contract, or does it hit every
# Agent-ID-gated mint? Compare our contract against known Agent ID mints.
set -u
export PATH="$HOME/.hermes/tools/node-26.12.1-linux-x64/bin:$PATH"
export NODE_OPTIONS="--require $HOME/.config/dnspin/pin_dns.cjs"
W=0x1C73877184F0071781E94F17b2d10704022a85BA

preview () {
  echo "=== $1 ($2)"
  timeout 120 baw contract-call preview --binanceChainId 56 --from "$W" \
    --to "$2" --value 0 --inputData "$3" --json 2>&1 \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print('OK' if d.get('success') else 'FAIL: '+str(d.get('error',{}).get('message'))[:150])"
}

# our contract
preview "AgentPermit.mintBadge" 0x25dfbcffcc844012f7dab492e863906de5a5609b 0x1249c58f
# known Agent ID gated mints from the MINTS index
preview "AgentDrop.mint()" 0x1dD8740FFcA0be3caaC3b4A3eb41FdFF506e38a9 0x1249c58f
preview "AgentPadPass.mint()" 0x01c106835091c09D5c69737631Af133530093C89 0x1249c58f
preview "AgentArena.mint()" 0xF11e9405b23CA0F53E6135162a85545D780a3737 0x1249c58f
# a plain view call on a random contract, control
preview "USDT.balanceOf (view)" 0x55d398326f99059fF775485246999027B3197955 0x70a082310000000000000000000000001c73877184f0071781e94f17b2d10704022a85ba
