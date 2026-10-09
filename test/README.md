# SPALACE test suite

Run `forge build` and `forge test` from the repository root. The suite uses the
existing Solidity 0.8.26/Cancun configuration, makes no network requests, needs no
RPC or environment variables, and does not enable FFI or filesystem cheatcodes.
All Solidity imports resolve to ordinary files in this repository.

| File | Coverage |
| --- | --- |
| `SPALACEToken.t.sol` | Identity and 1e27-unit mint to the constructor caller, factory-owned distribution, events, zero/whole/self transfers, finite and unlimited allowances, rollback, absent mint/burn/admin interfaces, and forbidden runtime opcodes. |
| `TokenEdges.t.sol` | Maximum finite allowances, revocation of unlimited approval, holder/spender isolation, self-transfer failures, maximum-value rejection, arbitrary recipients, contract recipients, same-block transfers, time passage, malformed calldata, and native-value rejection. |
| `Conservation.t.sol` | Random transfers, independent approvals/spends/revocations, and rejected operations, compared after every action to a separate balance and allowance ledger. Covers ordinary holders and the distributor/PoolManager addresses. |
| `PoolManager.t.sol` | Actual upstream v4 PoolManager at the specified Ethereum address: both currency orderings, economics-derived opening price, single-sided seeding within the 90% budget, whole 10% distributor transfer, rounding remainder, exact-input and exact-output buys/sells, LP fee accrual/collection, insufficient funds, one-unit underpayment rollback, and random swaps/fee claims. |

Fuzz tests use Foundry's default run count without overrides. The token invariant
uses 64 sequences of 64 actions; each of the two pool-order invariants uses 32
sequences of 24 actions. Unexpected handler reverts fail the tests. Pool invariant
settings are on the concrete test contracts so Foundry applies them to both
currency orderings. No long invariant campaign is required.

`PoolHarness.sol` settles negative v4 deltas using `sync`, an actual token
`transfer`, and `settle`; positive deltas are paid by the manager through `take`.
Tests compare the returned deltas with both parties' actual balance changes.
The pool charges the specified 12,500 hundredths of a basis point (1.25%);
SPALACE itself must deliver every transferred unit without a fee or burn. Failure
tests compare balances, supply, pool price/tick/liquidity, fee growth, and transient
settlement state before and after the rejected swap.

The fixture factory deploys the real token with CREATE2, so the constructor credits
an actual contract caller. It searches salts for each currency ordering rather
than moving the token runtime or manufacturing its balances. The manager's
constructor runs at the task's canonical address to preserve its address-bound
immutable. The paired token at the task's address is a minimal local ERC-20.
Dependency pins, licenses, and the one import-path adaptation are documented in
`vendor/README.md`; dependencies require no installation during verification.

The repository's existing `python3 scripts/check_manifest.py` validates the exact
manifest schema and values, ABI, and absence of linked libraries after building.
It is separate from `forge test` because the existing Foundry profile disables
filesystem cheatcode access. Required compiler settings were also checked directly
against `foundry.toml` without changing it.

These tests establish offline token/PoolManager compatibility. They do not claim a
mainnet-fork run or validation of the live paired currency, production launch
factory, initialization hook, or Merkle proof verification: those implementations
are not supplied here. The distributor test exercises the token transfer used to
pay a claim, not a replacement Merkle implementation. Live deployment integration
remains a separate check against those external contracts. No token defect was
identified by this suite.
