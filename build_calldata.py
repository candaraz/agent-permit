"""Build calldata for the deterministic CREATE2 deployer proxy.

The proxy (0x4e59b44847b379578588920cA78FbF26c0B4956C) expects:
    calldata = initcode || salt (32 bytes)
and returns the new contract address in the low 20 bytes of its return data.
"""
import json

ART = "/home/noodleo/agent-permit/out/AgentPermit.sol/AgentPermit.json"
REGISTRY = "60b9262456de011f7d15a54cdd8c48baaa8b022f"
PROXY = "0x4e59b44847b379578588920cA78FbF26c0B4956C"
SALT = "00" * 31 + "01"  # any 32-byte salt; fixed so the address is deterministic

art = json.load(open(ART))
bytecode = art["bytecode"]["object"]
if bytecode.startswith("0x"):
    bytecode = bytecode[2:]

initcode = bytecode + REGISTRY.rjust(64, "0")
# Layout confirmed empirically against the live proxy: salt comes FIRST,
# then the initcode. (initcode ++ salt reverts with StackUnderflow.)
calldata = SALT + initcode

out = {
    "proxy": PROXY,
    "initCode": "0x" + initcode,
    "salt": "0x" + SALT,
    "calldata": "0x" + calldata,
    "initCodeLen": len(initcode) // 2,
    "calldataLen": len(calldata) // 2,
    "expectedAddress": "0x25dfbcffcc844012f7dab492e863906de5a5609b",
}
json.dump(out, open("/home/noodleo/agent-permit/deploy-calldata.json", "w"), indent=1)
print("proxy:", PROXY)
print("initcode bytes:", out["initCodeLen"])
print("calldata bytes:", out["calldataLen"])
