#!/bin/bash
# Re-test the baw simulator with CORRECT selectors (previous run used
# 0x1249c58f = mint(address,uint256), not mint()).
set -u
export PATH="$HOME/.hermes/tools/node-26.12.1-linux-x64/bin:$PATH"
export NODE_OPTIONS="--require $HOME/.config/dnspin/pin_dns.cjs"
W=0x1C73877184F0071781E94F17b2d10704022a85BA

sig () { cast sig "$1"; }

preview () {
  local label="$1" to="$2" data="$3"
  echo -n "  $label -> "
  timeout 120 baw contract-call preview --binanceChainId 56 --from "$W" \
    --to "$to" --value 0 --inputData "$data" --json 2>&1 \
  | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    print('RAW parse fail'); raise SystemExit
if d.get('success'):
    print('OK  simCode=' + str(d['data']['simulationResult'].get('simulationCode')))
else:
    print('FAIL ' + str(d.get('error',{}).get('message'))[:90])
"
}

echo "selectors:"
echo "  mintBadge() = $(sig 'mintBadge()')"
echo "  mint()      = $(sig 'mint()')"

echo
echo "our contract:"
preview "AgentPermit.mintBadge() (0xda1b3cb0)" 0x25dfbcffcc844012f7dab492e863906de5a5609b "$(sig 'mintBadge()')"

echo "other Agent ID gated mints:"
preview "AgentDrop.mint()"      0x1dD8740FFcA0be3caaC3b4A3eb41FdFF506e38a9 "$(sig 'mint()')"
preview "AgentPadPass.mint()"  0x01c106835091c09D5c69737631Af133530093C89 "$(sig 'mint()')"
preview "AgentArena.mint()"    0xF11e9405b23CA0F53E6135162a85545D780a3737 "$(sig 'mint()')"

echo "control (ungated state change):"
preview "WBNB.deposit()" 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c 0xd0e30db0
