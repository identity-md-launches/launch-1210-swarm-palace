# Local review

This is the implementing worker's local review, not an independent audit or network attestation. No external reviewer or sub-agent was used.

## Findings and disposition

- **Supply and authority:** the only initial balance assignment is in the constructor, to `msg.sender`, for all 1e27 units. Total supply is constant and there are no privileged interfaces. Factory and stranger attempts to mint, burn, seize, pause or upgrade revert. No defect found.
- **Conservation:** transfers cannot create or destroy units. The checked balance precedes unchecked subtraction, and additions are bounded by the fixed total supply. Self-transfers read the recipient after the subtraction. Zero-address transfers cannot burn units. Fuzz and stateful tests found no conservation violation.
- **Allowances:** finite authorizations decrease exactly; unlimited authorizations persist; failed transfers roll back consumed allowance. No bypass for the deployer. Standard ERC-20 approval replacement ordering remains relevant and is documented.
- **Launch compatibility:** the local factory receives all supply. Distributor claims and token movements into/out of the specified PoolManager address arrive whole. The token makes no external protocol calls and contains no special address exemptions. Real pool initialization and swap settlement were not simulated locally.
- **Bytecode and configuration:** no libraries or remote imports; pinned solc 0.8.26/Cancun; optimizer enabled; bytecode hash disabled; FFI disabled and filesystem permissions empty. Runtime opcode scanning excludes delegatecall, callcode and selfdestruct, accounting for PUSH data. No proxy or fallback exists.
- **Manifest:** local checker enforces the six exact top-level keys, all requested pool/economic values, no-argument constructor, no application contracts, ABI match and runtime size limit. No pinned standalone admission schema was supplied; this task-specific check does not claim to replace network admission.
- **Artwork:** all five generated concepts and the selected image were inspected. The actual 64-pixel proof shows readable subjects and ticker on light/dark surfaces. The selected 32-pixel circular proof retains the crown, two eyes and smile. It has an opaque full-square purple background, no type and no badge frame. Other concepts are retained alternatives, not discarded drafts; the lettermark's text, the badge rim/texture and the meme's busy throne scene make them less suitable for the selected wallet image. Five drafts generated; zero redraws.

## Checks run

- `forge build --offline`: passed with solc 0.8.26.
- `forge test --offline`: 21 tests passed, including five fuzz tests and one stateful invariant.
- Second-seed fuzz and invariant run: seed `0x5350414c414345`; all 21 tests passed, with 2,000 cases per fuzz test and 256 invariant sequences of depth 64 (16,384 calls, zero reverts). The initial run used 1,000 cases per fuzz test; final inline settings preserve 2,000 cases for the offline verifier.
- `forge fmt` then `forge fmt --check`: passed.
- `EXPECTED_CHAIN_ID=0 forge script script/Deploy.s.sol:Deploy --offline`: passed, simulation only, no broadcast.
- `python3 scripts/check_manifest.py`: passed; exact manifest values and exported ABI match the build. Deployed token runtime is 1,315 bytes.
- `python3 scripts/check_assets.py` and image inspection tools: all six PNGs valid, opaque 1024 × 1024; selected image matches option 1 exactly. Review proofs are in `artifacts/previews/`.

The pinned protected test source was read. It depends on network-provided launch infrastructure contracts, environment values and predicted deployment addresses, so it was not misrepresented as part of the local test run. Live factory/pool integration and independent attestation are still the network's responsibility.

## Upload-size repair

Removed only the five redundant 1254 × 1254 originals from `artifacts/generated/`, saving 7,895,274 bytes. All five required 1024 × 1024 logo options, the selected `artifacts/logo.png`, preview proofs, source, tests and ABI remain. SHA-256 checks against the existing asset report confirmed that every deliverable PNG is unchanged. Updated both READMEs to describe the retained exports accurately. The remaining source files total approximately 7.26 MiB, below the 8 MiB upload limit even before archive compression.

After removal, reran the offline build, all 21 tests with both a fresh seed and `0x5350414c414345`, formatting and its check, the offline deployment simulation, and both Python checkers; all passed. Reinspected the 64-pixel options and selected 32-pixel circular proof. No additional artwork was generated; the original five designs are all retained as exports.
