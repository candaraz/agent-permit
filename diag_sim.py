#!/usr/bin/env python3
"""Diagnose why the baw simulator reverts on AgentPermit.mintBadge().

Hypothesis: the simulator's state snapshot predates the deployment, so the
target address has no code in its view. Compare:
  - eth_call from a plain wallet (expect our NotAgentId custom error)
  - eth_call from the Agent ID wallet (expect success)
  - baw preview, with and without --gasLimit
"""
import json, ssl, subprocess, urllib.request

ENV = {
    "PATH": "/home/noodleo/.hermes/tools/node-26.12.1-linux-x64/bin:/usr/local/bin:/usr/bin:/bin",
    "NODE_OPTIONS": "--require /home/noodleo/.config/dnspin/pin_dns.cjs",
    "HOME": "/home/noodleo",
}
C = "0x25dfbcffcc844012f7dab492e863906de5a5609b"
W = "0x1C73877184F0071781E94F17b2d10704022a85BA"
PLAIN = "0x1111111111111111111111111111111111111111"
RPC = "https://bsc-rpc.publicnode.com"
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE


def rpc(m, p):
    req = urllib.request.Request(
        RPC, data=json.dumps({"jsonrpc": "2.0", "method": m, "params": p, "id": 1}).encode(),
        headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=30, context=ctx).read().decode())


def ecall(frm, data):
    r = rpc("eth_call", [{"from": frm, "to": C, "data": data}, "latest"])
    return r.get("result"), r.get("error")


print("code at contract:", len(rpc("eth_getCode", [C, "latest"])["result"]) // 2 - 1, "bytes")
print("code at wallet   :", len(rpc("eth_getCode", [W, "latest"])["result"]) // 2 - 1, "bytes")

r, e = ecall(W, "0x1249c58f")
print("eth_call mintBadge from AGENT-ID wallet:", r, e)

r, e = ecall(PLAIN, "0x1249c58f")
print("eth_call mintBadge from plain wallet    :", r, e)

# blocks since deployment
dep = json.load(open("/home/noodleo/agent-permit/deployment.json"))["block"]
head = int(rpc("eth_blockNumber", [])["result"], 16)
print(f"deploy block {dep}, head {head}, age {head-dep} blocks")


def preview(label, frm, gas=None):
    cmd = ["baw", "contract-call", "preview", "--binanceChainId", "56", "--from", frm,
           "--to", C, "--value", "0", "--inputData", "0x1249c58f", "--json"]
    if gas:
        cmd += ["--gasLimit", str(gas)]
    p = subprocess.run(cmd, env=ENV, capture_output=True, text=True, timeout=180)
    try:
        d = json.loads(p.stdout)
        ok = d.get("success")
        print(f"  {label}: {'OK' if ok else 'FAIL ' + str(d.get('error', {}).get('message'))[:80]}")
        if ok:
            print("    simulationCode:", d["data"]["simulationResult"].get("simulationCode"))
    except Exception:
        print(f"  {label}: RAW {p.stdout[:160]} {p.stderr[:160]}")


print("baw preview:")
preview("from Agent ID wallet", W)
preview("from Agent ID wallet + gasLimit", W, 300000)
preview("from plain wallet", PLAIN)
