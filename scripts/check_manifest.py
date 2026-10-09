#!/usr/bin/env python3
"""Check the task's exact manifest shape and values against the built token ABI.

This is a task-specific consistency check, not a substitute for network admission.
Run forge build --offline first. Uses only Python's standard library.
"""

import json
from pathlib import Path


root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / "launch.json").read_text())
assert set(manifest) == {"kind", "token", "contracts", "pool", "economics", "notes"}
assert manifest["kind"] == "custom_token"
assert manifest["token"] == {
    "contract": "SPALACEToken", "name": "Swarm Palace", "symbol": "SPALACE",
    "decimals": 18, "constructorArgs": [], "totalSupply": "1000000000000000000000000000",
}
assert manifest["contracts"] == []
assert manifest["pool"] == {
    "pairedCurrency": "0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7",
    "fee": 12500, "tickSpacing": 60, "initialPrice": "125270724187523965593206900",
}
assert manifest["economics"] == {
    "poolBps": 9000, "initialMarketCapWei": "2500000000000000000000",
    "remainderTo": "0x000000000000000000000000000000000000dead",
}
assert isinstance(manifest["notes"], str) and manifest["notes"].strip()
artifact = json.loads((root / "out" / "SPALACEToken.sol" / "SPALACEToken.json").read_text())
abi = artifact["abi"]
constructors = [item for item in abi if item["type"] == "constructor"]
assert len(constructors) == 1 and constructors[0]["inputs"] == []
assert {item["name"] for item in abi if item["type"] == "function"} == {
    "name", "symbol", "decimals", "totalSupply", "balanceOf", "allowance", "transfer", "approve", "transferFrom",
}
assert not artifact["bytecode"].get("linkReferences")
assert not artifact["deployedBytecode"].get("linkReferences")
code = artifact["deployedBytecode"]["object"].removeprefix("0x")
assert 0 < len(code) // 2 <= 24576
assert json.loads((root / "docs" / "abi" / "SPALACEToken.json").read_text()) == abi
print(json.dumps({"manifest": "matches task", "abi": "matches build", "runtimeBytes": len(code) // 2}))
