# Offline PoolManager test dependencies

These ordinary Solidity files are the transitive import closure used by the tests;
there are no submodules, package installation steps, or network reads at test time.

- Uniswap v4-core v4.0.0, commit `e50237c43811bd9b526eff40f26772152a42daba`:
  https://github.com/Uniswap/v4-core/tree/e50237c43811bd9b526eff40f26772152a42daba
- Solmate, pinned by that v4-core release, commit `4b47a19038b798b4a33d9749d25e570443520647`:
  https://github.com/transmissions11/solmate/tree/4b47a19038b798b4a33d9749d25e570443520647

Licenses are included beside each dependency; individual source SPDX identifiers
are retained. The sole source adjustment is the import in
`v4-core/src/ProtocolFees.sol`: `solmate/src/auth/Owned.sol` becomes
`../../solmate/src/auth/Owned.sol`, allowing the existing project to compile with
no remappings or configuration changes. All other dependency code is upstream.

The manager is for local integration tests only. It is constructed in place at
the task's mainnet PoolManager address to preserve its NoDelegateCall immutable.
This does not verify Ethereum live state. The paired currency is a test ERC-20
placed at the task's paired-currency address.
