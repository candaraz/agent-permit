#!/usr/bin/env python3
"""Verify the deployed AgentPermit on BSC and mint the first badge from the Agent ID wallet."""
import json, subprocess, sys, time, urllib.request, ssl

ENV = {
    "PATH": "/home/noodleo/.hermes/tools/node-26.12.1-linux-x64/bin:"
            "/home/noodleo/.foundry/bin:/usr/local/bin:/usr/bin:/bin",
    "NODE_OPTIONS": "--require /home/noodleo/.config/dnspin/pin_dns.cjs",
    "HOME": "/home/noodleo",
}
CONTRACT = "0x25dfbcffcc844012f7dab492e863906de5a5609b"
WALLET = "0x1C73877184F0071781E94F17b2d10704022a85BA"
AID = "0x60b9262456de011f7d15a54cdd8c48baaa8b022f"
RPC = "https://bsc-rpc.publicnode.com"

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE


def rpc(m, p):
    req = urllib.request.Request(
        RPC, data=json.dumps({"jsonrpc": "2.0", "method": m, "params": p, "id": 1}).encode(),
        headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=30, context=ctx).read().decode())


def call(to, data):
    r = rpc("eth_call", [{"to": to, "data": data}, "latest"])
    if "error" in r:
        return None, r["error"]
    return r["result"], None


def baw(*args):
    p = subprocess.run(["baw", *args], env=ENV, capture_output=True, text=True, timeout=300)
    if p.returncode != 0:
        return {"success": False, "stderr": p.stderr[:400], "stdout": p.stdout[:400]}
    try:
        return json.loads(p.stdout)
    except Exception:
        return {"success": None, "stdout": p.stdout[:600]}


def dec_str(hexstr):
    raw = bytes.fromhex(hexstr[2:])
    off = int.from_bytes(raw[0:32], "big")
    ln = int.from_bytes(raw[off:off + 32], "big")
    return raw[off + 32:off + 32 + ln].decode(errors="replace")


print("=== deployed contract checks")
code = rpc("eth_getCode", [CONTRACT, "latest"])["result"]
print("code bytes:", len(code) // 2 - 1)

# holdsAgentId(address) = 0x11213086
r, err = call(CONTRACT, "0x11213086" + WALLET[2:].rjust(64, "0"))
print("holdsAgentId(wallet):", r, err)

# handleOf(address) = 0xc50a1514
r, err = call(CONTRACT, "0xc50a1514" + WALLET[2:].rjust(64, "0"))
print("handleOf(wallet):", dec_str(r) if r else r, err)

# badgeOf(address) = keccak("badgeOf(address)") -> computed below via cast
import subprocess as sp
sel = sp.run(["cast", "sig", "badgeOf(address)"], env=ENV, capture_output=True, text=True).stdout.strip()
r, err = call(CONTRACT, sel + WALLET[2:].rjust(64, "0"))
print(f"badgeOf(wallet) [{sel}]:", int(r, 16) if r else r, err)

# totalSupply via ERC721Enumerable
sel_ts = sp.run(["cast", "sig", "totalSupply()"], env=ENV, capture_output=True, text=True).stdout.strip()
r, err = call(CONTRACT, sel_ts)
print("totalSupply:", int(r, 16) if r else r, err)

print()
print("=== mint badge from the Agent ID wallet")
prev = baw("contract-call", "preview", "--binanceChainId", "56",
           "--from", WALLET, "--to", CONTRACT, "--value", "0",
           "--inputData", "0x" + sp.run(["cast", "sig", "mintBadge()"], env=ENV,
                                        capture_output=True, text=True).stdout.strip(),
           "--json")
if not prev.get("success"):
    print("PREVIEW FAILED:", json.dumps(prev)[:900])
    sys.exit(1)
print("preview requestId:", prev["data"]["requestId"])
print("  balanceChanges:", prev["data"].get("simulationResult", {}).get("balanceChanges"))

res = baw("contract-call", "execute", "--requestId", prev["data"]["requestId"], "--json")
print("EXECUTE:", json.dumps(res)[:800])
if not res.get("success"):
    sys.exit(2)
tx = res.get("data", {}).get("txHash", "")
print("txHash:", tx)

for _ in range(30):
    time.sleep(3)
    rc = rpc("eth_getTransactionReceipt", [tx])
    if rc.get("result"):
        print("status:", int(rc["result"]["status"], 16), "gasUsed:", int(rc["result"]["gasUsed"], 16))
        r, err = call(CONTRACT, sel + WALLET[2:].rjust(64, "0"))
        print("badgeOf(wallet) after mint:", int(r, 16) if r else r, err)
        r, err = call(CONTRACT, sel_ts)
        print("totalSupply after mint:", int(r, 16) if r else r, err)
        break
else:
    print("no receipt")
