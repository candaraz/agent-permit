#!/usr/bin/env python3
"""Mint the first AgentPermit badge from the Binance Agentic Wallet (the Agent ID wallet)."""
import json, subprocess, sys, time, urllib.request, ssl

ENV = {
    "PATH": "/home/noodleo/.hermes/tools/node-26.12.1-linux-x64/bin:/usr/local/bin:/usr/bin:/bin",
    "NODE_OPTIONS": "--require /home/noodleo/.config/dnspin/pin_dns.cjs",
    "HOME": "/home/noodleo",
}
C = "0x25dfbcffcc844012f7dab492e863906de5a5609b"
W = "0x1C73877184F0071781E94F17b2d10704022a85BA"
RPC = "https://bsc-rpc.publicnode.com"
MINT = "0xda1b3cb0"  # mintBadge()

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE


def rpc(m, p):
    req = urllib.request.Request(
        RPC, data=json.dumps({"jsonrpc": "2.0", "method": m, "params": p, "id": 1}).encode(),
        headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=30, context=ctx).read().decode())


def baw(*a):
    p = subprocess.run(["baw", *a], env=ENV, capture_output=True, text=True, timeout=300)
    try:
        return json.loads(p.stdout)
    except Exception:
        print("RAW:", p.stdout[:400], p.stderr[:400])
        sys.exit(1)


def call(data):
    r = rpc("eth_call", [{"from": W, "to": C, "data": data}, "latest"])
    return r.get("result"), r.get("error")


print("before: badgeOf =", call("0x5b9b1dce" + W[2:].rjust(64, "0"))[0])

prev = baw("contract-call", "preview", "--binanceChainId", "56", "--from", W,
           "--to", C, "--value", "0", "--inputData", MINT, "--json")
if not prev.get("success"):
    print("PREVIEW FAILED:", json.dumps(prev)[:800])
    sys.exit(1)
print("preview OK requestId:", prev["data"]["requestId"])

res = baw("contract-call", "execute", "--requestId", prev["data"]["requestId"], "--json")
print("EXECUTE:", json.dumps(res)[:600])
if not res.get("success"):
    sys.exit(2)
tx = res["data"].get("txHash", "")
print("txHash:", tx)

for _ in range(30):
    time.sleep(3)
    rc = rpc("eth_getTransactionReceipt", [tx])
    if rc.get("result"):
        st = int(rc["result"]["status"], 16)
        print("status:", st, "gasUsed:", int(rc["result"]["gasUsed"], 16))
        print("badgeOf:", call("0x5b9b1dce" + W[2:].rjust(64, "0"))[0])
        print("totalSupply:", call("0x18160ddd")[0])
        print("ownerOf(1):", rpc("eth_call", [{"to": C, "data": "0x6352211e" + "1".rjust(64, "0")}, "latest"]).get("result"))
        if st == 1:
            json.dump({"badgeTokenId": 1, "txHash": tx, "contract": C},
                      open("/home/noodleo/agent-permit/badge-mint.json", "w"), indent=1)
            print("MINTED -> badge-mint.json written")
        break
else:
    print("no receipt")
