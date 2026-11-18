"""Build the AgentPermit creation calldata (init code + constructor arg).

The constructor takes the SPACE ID Agent ID registry address:
  0x60b9262456de011f7d15a54cdd8c48baaa8b022f
"""
import json, sys

ART = "/home/noodleo/agent-permit/out/AgentPermit.sol/AgentPermit.json"
REGISTRY = "60b9262456de011f7d15a54cdd8c48baaa8b022f"

art = json.load(open(ART))
bytecode = art["bytecode"]["object"]
if bytecode.startswith("0x"):
    bytecode = bytecode[2:]

arg = REGISTRY.rjust(64, "0")
initcode = bytecode + arg

print("initcode hex len:", len(initcode))
out = {"initCode": "0x" + initcode, "length": len(initcode)}
json.dump(out, open("/home/noodleo/agent-permit/deploy-initcode.json", "w"))
print("written /home/noodleo/agent-permit/deploy-initcode.json")
print("prefix:", "0x" + initcode[:40])
print("suffix:", initcode[-40:])
