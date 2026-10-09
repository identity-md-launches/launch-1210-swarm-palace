// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SPALACEToken} from "../src/SPALACEToken.sol";
import {TestVm} from "./SPALACEToken.t.sol";
import {PoolManager} from "./vendor/v4-core/src/PoolManager.sol";
import {IPoolManager} from "./vendor/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "./vendor/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "./vendor/v4-core/src/types/PoolKey.sol";
import {Currency} from "./vendor/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "./vendor/v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "./vendor/v4-core/src/libraries/TickMath.sol";
import {FullMath} from "./vendor/v4-core/src/libraries/FullMath.sol";
import {StateLibrary} from "./vendor/v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "./vendor/v4-core/src/libraries/TransientStateLibrary.sol";
import {HarnessERC20, PairedCurrencyFixture, PoolActor, LaunchFactoryFixture} from "./helpers/PoolHarness.sol";

interface PoolTestVm is TestVm {
    function etch(address target, bytes calldata code) external;
    function chainId(uint256 chainId_) external;
}

interface PoolSequenceTarget {
    function sequenceTrade(bool sellToken, uint256 amountSeed) external;
    function sequenceCollect() external;
}

/// @dev Keeps random targeting on useful actions, away from test fixtures' setup/mint methods.
contract PoolSequenceHandler {
    PoolSequenceTarget private immutable target;

    constructor(PoolSequenceTarget target_) {
        target = target_;
    }

    function trade(bool sellToken, uint256 amountSeed) external {
        target.sequenceTrade(sellToken, amountSeed);
    }

    function collectFees() external {
        target.sequenceCollect();
    }
}

/// @dev Offline integration with upstream v4-core, not a fork or a mocked swap.
/// Factory and paired currency are local fixtures; no production factory/hook/distributor is supplied.
abstract contract PoolManagerTestBase {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    PoolTestVm private constant vm = PoolTestVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address internal constant MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant PAIRED = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;
    address internal constant DISTRIBUTOR = address(0xD157);
    address internal constant REMAINDER_TO = 0x000000000000000000000000000000000000dEaD;
    uint256 internal constant SUPPLY = 1e27;
    uint256 internal constant MARKET_CAP = 2500e18;
    uint256 private constant Q96 = 1 << 96;

    IPoolManager internal manager;
    SPALACEToken internal token;
    PairedCurrencyFixture internal paired;
    LaunchFactoryFixture internal factory;
    PoolActor internal trader;
    PoolKey internal key;
    int24 internal lower;
    int24 internal upper;
    uint256 internal seeded;
    uint256 internal remainder;
    PoolSequenceHandler private sequenceHandler;

    function tokenIsZero() internal pure virtual returns (bool);

    function setUp() public {
        vm.chainId(1);
        // Execute the constructor at the canonical address: copying a deployed runtime
        // would break the manager's NoDelegateCall immutable.
        vm.etch(MANAGER, abi.encodePacked(type(PoolManager).creationCode, abi.encode(address(this))));
        (bool built, bytes memory runtime) = MANAGER.call("");
        require(built && runtime.length > 0, "manager construction failed");
        vm.etch(MANAGER, runtime);
        manager = IPoolManager(MANAGER);
        vm.etch(PAIRED, address(new PairedCurrencyFixture()).code);
        paired = PairedCurrencyFixture(PAIRED);
        factory = new LaunchFactoryFixture(manager);
        token = factory.deploy(tokenIsZero(), PAIRED);
        trader = new PoolActor(manager);

        require(token.balanceOf(address(factory)) == SUPPLY, "factory did not receive whole mint");
        require(token.balanceOf(DISTRIBUTOR) == 0, "token distributed swarm itself");
        require(token.balanceOf(MANAGER) == 0, "token seeded itself");
        factory.move(HarnessERC20(address(token)), DISTRIBUTOR, SUPPLY / 10);

        key = PoolKey({
            currency0: Currency.wrap(tokenIsZero() ? address(token) : PAIRED),
            currency1: Currency.wrap(tokenIsZero() ? PAIRED : address(token)),
            fee: 12_500,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        // Derive sqrt(currency1/currency0) from economics using the deployed ordering.
        uint256 numerator = tokenIsZero() ? MARKET_CAP : SUPPLY;
        uint256 denominator = tokenIsZero() ? SUPPLY : MARKET_CAP;
        uint160 price = uint160(_sqrt(FullMath.mulDiv(numerator, 1 << 192, denominator)));
        if (tokenIsZero()) require(price == 125270724187523965593206900, "opening price provenance");
        int24 tick = manager.initialize(key, price);
        int24 compressed = tick / key.tickSpacing;
        if (tick < 0 && tick % key.tickSpacing != 0) --compressed;
        lower = tokenIsZero() ? (compressed + 1) * key.tickSpacing : TickMath.minUsableTick(key.tickSpacing);
        upper = tokenIsZero() ? TickMath.maxUsableTick(key.tickSpacing) : compressed * key.tickSpacing;
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(lower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(upper);
        uint256 budget = SUPPLY * 9000 / 10_000;
        uint256 liquidity = tokenIsZero()
            ? FullMath.mulDiv(budget, FullMath.mulDiv(sqrtLower, sqrtUpper, Q96), sqrtUpper - sqrtLower)
            : FullMath.mulDiv(budget, Q96, sqrtUpper - sqrtLower);
        require(liquidity > 0 && liquidity <= uint256(uint128(type(int128).max)), "liquidity bounds");
        (BalanceDelta delta,) = factory.modify(key, lower, upper, int256(liquidity));
        require(_pairDelta(delta) == 0, "launch must be single-sided");
        seeded = uint256(-int256(_tokenDelta(delta)));
        require(seeded > 0 && seeded <= budget, "seed exceeded 90% budget");
        require(token.balanceOf(MANAGER) == seeded, "seed arrived short");
        remainder = budget - seeded;
        factory.move(HarnessERC20(address(token)), REMAINDER_TO, remainder);
        require(token.balanceOf(address(factory)) == 0, "factory kept remainder");
        paired.mint(address(trader), 10 ether);
        sequenceHandler = new PoolSequenceHandler(PoolSequenceTarget(address(this)));
        _assertConservation();
    }

    function targetContracts() external view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(sequenceHandler);
    }

    function sequenceTrade(bool sellToken, uint256 amountSeed) external {
        require(msg.sender == address(sequenceHandler), "sequence handler only");
        uint256 available = sellToken ? token.balanceOf(address(trader)) : paired.balanceOf(address(trader));
        if (!sellToken && available > 0.1 ether) available = 0.1 ether;
        if (available == 0) return;
        _checkedSwap(sellToken, -int256(1 + amountSeed % available));
    }

    function sequenceCollect() external {
        require(msg.sender == address(sequenceHandler), "sequence handler only");
        uint256 tokenBefore = token.balanceOf(address(factory));
        uint256 pairBefore = paired.balanceOf(address(factory));
        (BalanceDelta delta, BalanceDelta fees) = factory.modify(key, lower, upper, 0);
        require(BalanceDelta.unwrap(delta) == BalanceDelta.unwrap(fees), "fee-only delta mismatch");
        require(_tokenDelta(fees) >= 0 && _pairDelta(fees) >= 0, "negative fee claim");
        require(token.balanceOf(address(factory)) - tokenBefore == uint128(_tokenDelta(fees)), "fee token shortfall");
        require(paired.balanceOf(address(factory)) - pairBefore == uint128(_pairDelta(fees)), "fee pair shortfall");
    }

    function _assertPoolInvariant() internal view {
        _assertConservation();
        require(token.balanceOf(DISTRIBUTOR) == SUPPLY / 10, "trading moved swarm allocation");
        require(token.balanceOf(REMAINDER_TO) == remainder, "trading moved remainder");
    }

    function test_SingleSidedLaunchAndDistributorTransferArriveWhole() public {
        require(block.chainid == 1, "wrong fixture chain");
        require((address(token) < PAIRED) == tokenIsZero(), "currency order not exercised");
        require(key.fee == 12_500 && key.tickSpacing == 60, "pool parameters");
        require(token.balanceOf(DISTRIBUTOR) == SUPPLY / 10, "swarm allocation short");
        require(token.balanceOf(REMAINDER_TO) == remainder, "remainder short");
        require(paired.balanceOf(MANAGER) == 0, "pair required for seed");
        vm.prank(DISTRIBUTOR);
        require(token.transfer(address(trader), SUPPLY / 10), "claim transfer failed");
        require(token.balanceOf(address(trader)) == SUPPLY / 10, "claim transfer taxed");
        require(token.balanceOf(DISTRIBUTOR) == 0, "claim left residue");
        _assertConservation();
    }

    function test_BuySellAndCollectFeesThroughPoolManager() public {
        _roundTrip(0.01 ether);
        (uint256 growth0, uint256 growth1) = manager.getFeeGrowthGlobals(key.toId());
        require(growth0 > 0 && growth1 > 0, "fees not accrued on both swap inputs");
        uint256 tokenBefore = token.balanceOf(address(factory));
        uint256 pairBefore = paired.balanceOf(address(factory));
        uint256 managerBefore = token.balanceOf(MANAGER);
        (BalanceDelta delta, BalanceDelta fees) = factory.modify(key, lower, upper, 0);
        require(BalanceDelta.unwrap(delta) == BalanceDelta.unwrap(fees), "fee-only collection");
        require(_tokenDelta(fees) > 0 && _pairDelta(fees) > 0, "no LP fees collected");
        uint256 tokenFees = uint128(_tokenDelta(fees));
        uint256 pairFees = uint128(_pairDelta(fees));
        require(token.balanceOf(address(factory)) - tokenBefore == tokenFees, "token fees arrived short");
        require(paired.balanceOf(address(factory)) - pairBefore == pairFees, "pair fees arrived short");
        require(managerBefore - token.balanceOf(MANAGER) == tokenFees, "manager token fee debit");
        _assertConservation();
    }

    function testFuzz_ExactInputBuySellConservesTokens(uint256 rawInput) public {
        _roundTrip(1e12 + rawInput % (1e17 - 1e12 + 1));
    }

    function test_ExactOutputBuyAndSellSettleWithoutTokenTax() public {
        BalanceDelta buy = _checkedSwap(false, int256(100e18));
        require(_tokenDelta(buy) == int128(100e18), "exact token output short");
        require(_pairDelta(buy) < 0, "buy did not pay pair");
        BalanceDelta sell = _checkedSwap(true, int256(1e13));
        require(_pairDelta(sell) == int128(1e13), "exact pair output short");
        require(_tokenDelta(sell) < 0, "sell did not pay token");
    }

    function test_OneUnitShortPaymentRevertsEntireBuyAndSell() public {
        bytes32 beforeBuy = _snapshot();
        vm.expectRevert(abi.encodeWithSelector(IPoolManager.CurrencyNotSettled.selector));
        trader.swapShortOne(key, !tokenIsZero(), -int256(0.01 ether));
        require(_snapshot() == beforeBuy, "failed buy changed balances, price or fees");
        _checkedSwap(false, -int256(0.01 ether));
        uint256 bought = token.balanceOf(address(trader));
        bytes32 beforeSell = _snapshot();
        vm.expectRevert(abi.encodeWithSelector(IPoolManager.CurrencyNotSettled.selector));
        trader.swapShortOne(key, tokenIsZero(), -int256(bought));
        require(_snapshot() == beforeSell, "failed sell changed balances, price or fees");
        _checkedSwap(true, -int256(bought));
    }

    function test_InsufficientTokenBalanceRevertsWholeSwap() public {
        // Move the price into the seeded range, then sell one more unit than owned.
        _checkedSwap(false, -int256(0.01 ether));
        uint256 bought = token.balanceOf(address(trader));
        bytes32 beforeSwap = _snapshot();
        vm.expectRevert(
            abi.encodeWithSelector(SPALACEToken.ERC20InsufficientBalance.selector, address(trader), bought, bought + 1)
        );
        trader.swap(key, tokenIsZero(), -int256(bought + 1));
        require(_snapshot() == beforeSwap, "unfunded sell changed pool or token state");
        _assertConservation();
    }

    function test_ZeroSwapAndLockedTakeCannotMoveValue() public {
        bytes32 beforeSwap = _snapshot();
        vm.expectRevert(abi.encodeWithSelector(IPoolManager.SwapAmountCannotBeZero.selector));
        trader.swap(key, !tokenIsZero(), 0);
        vm.expectRevert(abi.encodeWithSelector(IPoolManager.ManagerLocked.selector));
        manager.take(Currency.wrap(address(token)), address(trader), 1);
        require(_snapshot() == beforeSwap, "rejected operations changed pool state");
    }

    function _roundTrip(uint256 amountIn) internal {
        uint256 pairBefore = paired.balanceOf(address(trader));
        uint256 managerBefore = token.balanceOf(MANAGER);
        BalanceDelta buy = _checkedSwap(false, -int256(amountIn));
        require(_pairDelta(buy) == -int128(int256(amountIn)), "partial buy input");
        uint256 bought = token.balanceOf(address(trader));
        require(bought > 0 && bought == uint128(_tokenDelta(buy)), "buy arrived short");
        require(managerBefore - token.balanceOf(MANAGER) == bought, "buy manager debit");
        BalanceDelta sell = _checkedSwap(true, -int256(bought));
        require(_tokenDelta(sell) == -int128(int256(bought)), "partial sell input");
        require(_pairDelta(sell) > 0, "sell gave no pair");
        require(token.balanceOf(address(trader)) == 0, "sell left token residue");
        require(token.balanceOf(MANAGER) == managerBefore, "round trip burned or diverted tokens");
        require(paired.balanceOf(address(trader)) < pairBefore, "fee-bearing round trip was free");
        (,, uint24 protocolFee, uint24 lpFee) = manager.getSlot0(key.toId());
        require(protocolFee == 0 && lpFee == 12_500, "wrong pool fee");
    }

    function _checkedSwap(bool sellToken, int256 specified) internal returns (BalanceDelta delta) {
        uint256 tokenBefore = token.balanceOf(address(trader));
        uint256 pairBefore = paired.balanceOf(address(trader));
        uint256 managerToken = token.balanceOf(MANAGER);
        uint256 managerPair = paired.balanceOf(MANAGER);
        delta = trader.swap(key, sellToken ? tokenIsZero() : !tokenIsZero(), specified);
        int256 tokenDelta = _tokenDelta(delta);
        int256 pairDelta = _pairDelta(delta);
        require(int256(token.balanceOf(address(trader))) - int256(tokenBefore) == tokenDelta, "trader token delta");
        require(int256(paired.balanceOf(address(trader))) - int256(pairBefore) == pairDelta, "trader pair delta");
        require(int256(token.balanceOf(MANAGER)) - int256(managerToken) == -tokenDelta, "manager token delta");
        require(int256(paired.balanceOf(MANAGER)) - int256(managerPair) == -pairDelta, "manager pair delta");
        _assertConservation();
    }

    function _assertConservation() internal view {
        require(token.totalSupply() == SUPPLY, "supply changed during launch or swap");
        require(
            token.balanceOf(address(factory)) + token.balanceOf(MANAGER) + token.balanceOf(DISTRIBUTOR)
                    + token.balanceOf(address(trader)) + token.balanceOf(REMAINDER_TO) == SUPPLY,
            "token conservation"
        );
        require(token.balanceOf(address(token)) == 0 && token.balanceOf(address(0)) == 0, "hidden token sink");
        require(
            paired.balanceOf(address(trader)) + paired.balanceOf(MANAGER) + paired.balanceOf(address(factory))
                == paired.totalSupply(),
            "pair conservation"
        );
        require(manager.getNonzeroDeltaCount() == 0 && !manager.isUnlocked(), "unsettled pool accounting");
        require(
            manager.currencyDelta(address(trader), key.currency0) == 0
                && manager.currencyDelta(address(trader), key.currency1) == 0,
            "trader debt remains"
        );
    }

    function _snapshot() internal view returns (bytes32) {
        (uint160 price, int24 tick, uint24 protocolFee, uint24 lpFee) = manager.getSlot0(key.toId());
        (uint256 growth0, uint256 growth1) = manager.getFeeGrowthGlobals(key.toId());
        return keccak256(
            abi.encode(
                token.balanceOf(MANAGER),
                paired.balanceOf(MANAGER),
                token.balanceOf(address(trader)),
                paired.balanceOf(address(trader)),
                token.totalSupply(),
                price,
                tick,
                protocolFee,
                lpFee,
                growth0,
                growth1,
                manager.getLiquidity(key.toId()),
                manager.getNonzeroDeltaCount(),
                manager.isUnlocked()
            )
        );
    }

    function _tokenDelta(BalanceDelta delta) internal pure returns (int128) {
        return tokenIsZero() ? delta.amount0() : delta.amount1();
    }

    function _pairDelta(BalanceDelta delta) internal pure returns (int128) {
        return tokenIsZero() ? delta.amount1() : delta.amount0();
    }

    function _sqrt(uint256 value) private pure returns (uint256 result) {
        result = value;
        uint256 candidate = value / 2 + 1;
        while (candidate < result) {
            result = candidate;
            candidate = (value / candidate + candidate) / 2;
        }
    }
}

contract PoolManagerToken0Test is PoolManagerTestBase {
    function tokenIsZero() internal pure override returns (bool) {
        return true;
    }

    /// forge-config: default.invariant.runs = 32
    /// forge-config: default.invariant.depth = 24
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_SwapsAndFeeClaimsPreserveSupplyAndSettleAllDebt() public view {
        _assertPoolInvariant();
    }
}

contract PoolManagerToken1Test is PoolManagerTestBase {
    function tokenIsZero() internal pure override returns (bool) {
        return false;
    }

    /// forge-config: default.invariant.runs = 32
    /// forge-config: default.invariant.depth = 24
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_SwapsAndFeeClaimsPreserveSupplyAndSettleAllDebt() public view {
        _assertPoolInvariant();
    }
}
