#!/usr/bin/env python3
"""Deploy AgentPermit from the Binance Agentic Wallet (the Agent ID wallet).

Flow: preview -> execute -> read back the receipt from a public BSC RPC.
The private key never leaves the wallet: signing happens inside Binance Wallet.
"""
import json, subprocess, sys, time, urllib.request, ssl

EXPORT = "/home/noodleo/.hermes/tools/node-26.12.1-linux-x64/bin"
ENV = {
    "PATH": "/home/noodleo/.hermes/tools/node-26.12.1-linux-x64/bin:"
            "/home/noodleo/.foundry/bin:/usr/local/bin:/usr/bin:/bin",
    "NODE_OPTIONS": "--require /home/noodleo/.config/dnspin/pin_dns.cjs",
    "HOME": "/home/noodleo",
}
FROM = "0x1C73877184F0071781E94F17b2d10704022a85BA"
ZERO = "0x0000000000000000000000000000000000000000"
RPC = "https://bsc-rpc.publicnode.com"

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE


def rpc(method, params):
    req = urllib.request.Request(
        RPC, data=json.dumps({"jsonrpc": "2.0", "method": method, "params": params, "id": 1}).encode(),
        headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=30, context=ctx).read().decode())


def baw(*args):
    p = subprocess.run(["baw", *args], env=ENV, capture_output=True, text=True, timeout=300)
    if p.returncode != 0:
        print("BAW FAIL:", p.stderr[:800], p.stdout[:800])
        sys.exit(1)
    return json.loads(p.stdout)


initcode = json.load(open("/home/noodleo/agent-permit/deploy-initcode.json"))["initCode"]

nonce_before = int(rpc("eth_getTransactionCount", [FROM, "pending"])["result"], 16)
bal_before = int(rpc("eth_getBalance", [FROM, "latest"])["result"], 16)
print(f"deployer={FROM} nonce={nonce_before} balance={bal_before/1e18:.6f} BNB")

prev = baw("contract-call", "preview",
           "--binanceChainId", "56",
           "--from", FROM,
           "--to", ZERO,
           "--value", "0",
           "--inputData", initcode,
           "--gasLimit", "3000000",
           "--json")
if not prev.get("success"):
    print("PREVIEW FAILED:", json.dumps(prev)[:1200])
    sys.exit(1)

d = prev["data"]
print("preview requestId:", d["requestId"])
print("  risks:", json.dumps(d.get("risks", {}))[:200])
print("  allowanceChanges:", d.get("simulationResult", {}).get("allowanceChanges"))
print("  balanceChanges:", d.get("simulationResult", {}).get("balanceChanges"))
print("  requireConfirmation:", d.get("requireConfirmation"))

req_id = d["requestId"]
res = baw("contract-call", "execute", "--requestId", req_id, "--json")
print("EXECUTE:", json.dumps(res)[:1500])

if not res.get("success"):
    print("EXECUTE FAILED")
    sys.exit(2)

data = res.get("data", {})
tx_hash = (data.get("txHash") or data.get("hash") or "")
print("txHash:", tx_hash)

# wait for the receipt
for i in range(30):
    time.sleep(3)
    r = rpc("eth_getTransactionReceipt", [tx_hash])
    if r.get("result"):
        rc = r["result"]
        print("status:", int(rc["status"], 16), "gasUsed:", int(rc["gasUsed"], 16))
        print("contractAddress:", rc.get("contractAddress"))
        print("block:", int(rc["blockNumber"], 16))
        bal_after = int(rpc("eth_getBalance", [FROM, "latest"])["result"], 16)
        print(f"balance after: {bal_after/1e18:.6f} BNB (spent {(bal_before-bal_after)/1e18:.6f})")
        addr = rc.get("contractAddress")
        if addr and int(rc["status"], 16) == 1:
            code = rpc("eth_getCode", [addr, "latest"])["result"]
            print("deployed code length:", len(code) // 2 - 1, "bytes")
            out = {"contract": addr, "txHash": tx_hash,
                   "status": int(rc["status"], 16),
                   "gasUsed": int(rc["gasUsed"], 16),
                   "codeBytes": len(code) // 2 - 1,
                   "block": int(rc["blockNumber"], 16)}
            json.dump(out, open("/home/noodleo/agent-permit/deployment.json", "w"), indent=1)
            print("WROTE deployment.json")
        break
else:
    print("no receipt within timeout")
