#!/usr/bin/env python3
"""Check the deterministic CREATE2 deployer proxy on BSC.

Arachnid's / Nick's deterministic deployment proxy:
  0x4e59b44847b379578588920cA78FbF26c0B4956C
It does CREATE2 with a zero salt and runs the supplied initcode in the new
contract's context. If it is permissionless we can deploy through it with a
plain `baw contract-call`, which is not gated by the Binance Wallet address book.
"""
import json, urllib.request, ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

RPC = "https://bsc-rpc.publicnode.com"
PROXY = "0x4e59b44847b379578588920cA78FbF26c0B4956C"


def rpc(m, p):
    req = urllib.request.Request(
        RPC, data=json.dumps({"jsonrpc": "2.0", "method": m, "params": p, "id": 1}).encode(),
        headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=30, context=ctx).read().decode())


code = rpc("eth_getCode", [PROXY, "latest"])["result"]
print("proxy code bytes:", len(code) // 2 - 1)
if len(code) <= 2:
    raise SystemExit("proxy has no code - not deployed")

initcode = json.load(open("/home/noodleo/agent-permit/deploy-initcode.json"))["initCode"]

# eth_call the proxy with the initcode: if it simulates cleanly, creation works
r = rpc("eth_call", [{"to": PROXY, "data": initcode}, "latest"])
if "error" in r:
    print("SIMULATION ERROR:", json.dumps(r["error"])[:500])
else:
    print("simulation OK, returned:", (r.get("result") or "")[:120])

# any sender restriction? look for common owner/only-owner patterns in the runtime code
for needle, label in [("onlyowner", "onlyOwner"), ("caller", "caller-check"),
                      ("msg.sender", "msg.sender-ref"), ("revert", "revert"),
                      ("0000000000000000000000000000000000000000000000000000000000000000", "zero-addr")]:
    print(f"  {label}: {needle in code.lower()}")

# gas estimate for the proxy call
r = rpc("eth_estimateGas", [{"from": "0x1C73877184F0071781E94F17b2d10704022a85BA",
                             "to": PROXY, "data": initcode, "value": "0x0"}, "latest"])
if "error" in r:
    print("estimateGas error:", json.dumps(r["error"])[:300])
else:
    gas = int(r["result"], 16)
    print("estimateGas:", gas)
    gp = int(rpc("eth_gasPrice", [])["result"], 16)
    print(f"gasPrice: {gp} wei ({gp/1e9:.4f} gwei)")
    print(f"max cost: {gas*gp/1e18:.6f} BNB")
