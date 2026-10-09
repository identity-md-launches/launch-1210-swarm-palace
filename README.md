# Swarm Palace · SPALACE

Five original image-generated logo options are in [`logos/`](logos/README.md), with the selected crowned frog mascot at [`artifacts/logo.png`](artifacts/logo.png). Open [`logos/preview.html`](logos/preview.html) locally to compare the options at 64 pixels against light and dark backgrounds, and inspect the selected mark in a 32-pixel circular crop. No internet or external assets are needed to view it.

All six deliverable PNGs are opaque, 1024 × 1024 RGB. Five drafts were drawn by the built-in image generator, one per approach; all five are retained as the required exports. Only the lettermark contains text, the ticker SPALACE. The characters are original frogs, without existing copyrighted characters. `logos/README.md` records the selection and limitations of each alternative. The selected logo and small-size review proofs are retained under `artifacts/`. Redundant full-resolution originals are omitted to keep the source bundle below the 8 MiB upload limit.

## Token

`src/SPALACEToken.sol` is a dependency-free ERC-20. Its no-argument constructor mints exactly **1,000,000,000 tokens with 18 decimals (1e27 units)** to `msg.sender`. Supply is a constant forever. There is no owner, admin, further minting, burning, fee, tax, transfer limit, proxy or upgrade interface. No contract sends a swarm allocation itself.

The interface comprises `name`, `symbol`, `decimals`, `totalSupply`, `balanceOf`, `allowance`, `transfer`, `approve`, and `transferFrom`, plus standard `Transfer` and `Approval` events. The ABI is exported in [`docs/abi/SPALACEToken.json`](docs/abi/SPALACEToken.json). Finite allowances are consumed; maximum uint256 approvals remain unlimited. Zero-value and self-transfers work. Transfers to the zero address and approvals to a zero spender revert. Reverted transfers roll back allowance changes. As with ordinary ERC-20s, replacing an existing approval can be front-run by the spender; holders can revoke to zero before setting a replacement.

## Launch

`launch.json` contains the task's exact launch settings. The target is Ethereum mainnet; no chain ID is added to the manifest. The pair is IMD at `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, fee 12500 and tick spacing 60. The PoolManager is `0x000000000004444c5dc75cB358380D2e3dE08A90`.

The factory receives the full supply, forwards the swarm's 10% through its Merkle distributor, seeds the pool from its own balance under `poolBps: 9000`, and sends any remainder to the explicitly requested `0x000000000000000000000000000000000000dead`. The opening market cap is 2500 IMD (`2500000000000000000000` minor units). The manifest's `initialPrice` is provenance only; the network derives the actual opening price using the deployed token ordering and economics.

The network deployer handles production deployment through `ProjectFactory.launchCustom` after review. This repository reads no credentials, broadcasts no transactions and has no requester address to configure. `script/Deploy.s.sol` is a standalone simulation helper, not the factory launch workflow. For the operator to simulate its construction offline:

```sh
EXPECTED_CHAIN_ID=0 forge script script/Deploy.s.sol:Deploy --offline
```

The script defaults to a chain ID guard of 1; zero is an explicit local simulation override. Production factory invocation requires the network's deployment tooling and resolved launch inputs, which are not part of this assignment. Do not use the standalone script to distribute production supply.

## Offline checks

Foundry 1.8.3 and a cached solc 0.8.26 are required. All Solidity imports are repository-local; there are no packages, submodules or network dependencies. Compiler settings pin Cancun, optimizer 200 runs, metadata bytecode hash disabled, offline mode, FFI disabled and no filesystem permissions.

```sh
forge build --offline
forge test --offline
forge fmt --check
EXPECTED_CHAIN_ID=0 forge script script/Deploy.s.sol:Deploy --offline
python3 scripts/check_manifest.py
python3 scripts/check_assets.py
```

The manifest checker uses the compiled `out/` ABI only as an optional post-build check. Solidity tests never read generated files, image files or filesystem data. The asset checker needs system ffmpeg for review thumbnails; all logos are already delivered as PNGs, so no image-generation service or image-processing dependency is needed by the offline Foundry build/test verifier.

Tests cover factory allocation, fee-free launch token movements, authorization failures, approval revocation, unlimited allowances, zero and self-transfers, rollback, forbidden opcodes, fuzzed conservation and stateful conservation over four holders. The launch-flow test exercises token movements with a local factory stand-in; it does not claim to execute a real Uniswap swap. The externally supplied protected harness and a full mainnet factory/pool simulation remain the network verifier's checks. No fork RPC is required by the default suite.
