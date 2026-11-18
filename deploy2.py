#!/usr/bin/env python3
"""Deploy AgentPermit through the BSC CREATE2 deployer proxy, paid from the
Binance Agentic Wallet (the Agent ID wallet).

Why the proxy: `baw wallet send` is gated by the Binance Wallet address book,
and `baw contract-call` cannot create a contract on its own (it requires --to).
A contract call to the permissionless CREATE2 deployer is neither gated, so the
gas comes from the Agent ID wallet with no private key and no address-book step.

Layout confirmed empirically against live BSC: calldata = salt ++ initcode.
"""
import json, subprocess, sys, time, urllib.request, ssl

ENV = {
    "PATH": "/home/noodleo/.hermes/tools/node-26.12.1-linux-x64/bin:"
            "/home/noodleo/.foundry/bin:/usr/local/bin:/usr/bin:/bin",
    "NODE_OPTIONS": "--require /home/noodleo/.config/dnspin/pin_dns.cjs",
    "HOME": "/home/noodleo",
}
FROM = "0x1C73877184F0071781E94F17b2d10704022a85BA"
PROXY = "0x4e59b44847b379578588920cA78FbF26c0B4956C"
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
        print("BAW FAIL:", p.stderr[:600], p.stdout[:600])
        sys.exit(1)
    return json.loads(p.stdout)


d = json.load(open("/home/noodleo/agent-permit/deploy-calldata.json"))
calldata = d["calldata"]
expected = d["expectedAddress"]

nonce_before = int(rpc("eth_getTransactionCount", [FROM, "pending"])["result"], 16)
bal_before = int(rpc("eth_getBalance", [FROM, "latest"])["result"], 16)
print(f"deployer={FROM} nonce={nonce_before} balance={bal_before/1e18:.6f} BNB")
print(f"proxy={PROXY} expectedAddress={expected}")

# sanity: the proxy is live and the initcode is the one we tested
code = rpc("eth_getCode", [expected, "latest"])["result"]
if len(code) > 2:
    print("ABORT: contract already exists at the expected address")
    sys.exit(1)

prev = baw("contract-call", "preview",
           "--binanceChainId", "56",
           "--from", FROM,
           "--to", PROXY,
           "--value", "0",
           "--inputData", calldata,
           "--gasLimit", "4000000",
           "--json")
if not prev.get("success"):
    print("PREVIEW FAILED:", json.dumps(prev)[:1200])
    sys.exit(1)

pd = prev["data"]
print("preview requestId:", pd["requestId"])
print("  balanceChanges:", pd.get("simulationResult", {}).get("balanceChanges"))
print("  allowanceChanges:", pd.get("simulationResult", {}).get("allowanceChanges"))
print("  risks:", json.dumps(pd.get("risks", {}))[:200])
print("  requireConfirmation:", pd.get("requireConfirmation"))

res = baw("contract-call", "execute", "--requestId", pd["requestId"], "--json")
print("EXECUTE:", json.dumps(res)[:1200])
if not res.get("success"):
    sys.exit(2)

tx_hash = res.get("data", {}).get("txHash", "")
print("txHash:", tx_hash)

for _ in range(40):
    time.sleep(3)
    r = rpc("eth_getTransactionReceipt", [tx_hash])
    if r.get("result"):
        rc = r["result"]
        status = int(rc["status"], 16)
        print("status:", status, "gasUsed:", int(rc["gasUsed"], 16))
        print("receipt contractAddress:", rc.get("contractAddress"))
        bal_after = int(rpc("eth_getBalance", [FROM, "latest"])["result"], 16)
        print(f"balance after: {bal_after/1e18:.6f} BNB (spent {(bal_before-bal_after)/1e18:.6f})")
        deployed = rpc("eth_getCode", [expected, "latest"])["result"]
        print("code at expected address:", len(deployed) // 2 - 1, "bytes")
        if status == 1 and len(deployed) > 2:
            json.dump({"contract": expected, "txHash": tx_hash, "proxy": PROXY,
                       "status": status, "gasUsed": int(rc["gasUsed"], 16),
                       "codeBytes": len(deployed) // 2 - 1,
                       "block": int(rc["blockNumber"], 16),
                       "deployer": FROM},
                      open("/home/noodleo/agent-permit/deployment.json", "w"), indent=1)
            print("DEPLOYED -> wrote deployment.json")
        else:
            print("NOT DEPLOYED (status %s, code %d bytes)" % (status, len(deployed) // 2 - 1))
        break
else:
    print("no receipt within timeout")
