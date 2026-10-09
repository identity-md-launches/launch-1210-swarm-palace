// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SPALACEToken} from "../../src/SPALACEToken.sol";
import {IPoolManager} from "../vendor/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../vendor/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "../vendor/v4-core/src/types/PoolKey.sol";
import {Currency} from "../vendor/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "../vendor/v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "../vendor/v4-core/src/libraries/TickMath.sol";

interface HarnessERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address holder) external view returns (uint256);
}

/// @dev Test currency only: the live paired currency's implementation is not in this repository.
contract PairedCurrencyFixture {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "pair balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @dev A local liquidity provider/trader, not a replacement implementation of PoolManager.
/// It settles actual v4 deltas through sync -> transfer -> settle, and receives via take.
contract PoolActor is IUnlockCallback {
    IPoolManager public immutable manager;
    address public immutable controller;

    constructor(IPoolManager manager_) {
        manager = manager_;
        controller = msg.sender;
    }

    modifier onlyController() {
        require(msg.sender == controller, "fixture controller");
        _;
    }

    function move(HarnessERC20 token, address to, uint256 amount) external onlyController {
        require(token.transfer(to, amount), "transfer returned false");
    }

    function modify(PoolKey memory key, int24 lower, int24 upper, int256 liquidity)
        external
        onlyController
        returns (BalanceDelta delta, BalanceDelta fees)
    {
        IPoolManager.ModifyLiquidityParams memory params =
            IPoolManager.ModifyLiquidityParams(lower, upper, liquidity, bytes32(0));
        return abi.decode(manager.unlock(abi.encode(uint8(0), key, abi.encode(params))), (BalanceDelta, BalanceDelta));
    }

    function swap(PoolKey memory key, bool zeroForOne, int256 amountSpecified)
        external
        onlyController
        returns (BalanceDelta)
    {
        return _swap(key, zeroForOne, amountSpecified, false);
    }

    function swapShortOne(PoolKey memory key, bool zeroForOne, int256 amountSpecified)
        external
        onlyController
        returns (BalanceDelta)
    {
        return _swap(key, zeroForOne, amountSpecified, true);
    }

    function _swap(PoolKey memory key, bool zeroForOne, int256 amountSpecified, bool shortPay)
        private
        returns (BalanceDelta)
    {
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams(zeroForOne, amountSpecified, limit);
        return
            abi.decode(
                manager.unlock(abi.encode(shortPay ? uint8(2) : uint8(1), key, abi.encode(params))), (BalanceDelta)
            );
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "fixture manager");
        (uint8 action, PoolKey memory key, bytes memory parameters) = abi.decode(data, (uint8, PoolKey, bytes));
        BalanceDelta delta;
        BalanceDelta fees;
        if (action == 0) {
            (delta, fees) =
                manager.modifyLiquidity(key, abi.decode(parameters, (IPoolManager.ModifyLiquidityParams)), "");
        } else {
            delta = manager.swap(key, abi.decode(parameters, (IPoolManager.SwapParams)), "");
        }
        _settle(key.currency0, delta.amount0(), action == 2);
        _settle(key.currency1, delta.amount1(), action == 2);
        return action == 0 ? abi.encode(delta, fees) : abi.encode(delta);
    }

    function _settle(Currency currency, int128 delta, bool shortPay) private {
        if (delta < 0) {
            uint256 amount = uint256(-int256(delta));
            if (shortPay) --amount;
            manager.sync(currency);
            require(HarnessERC20(Currency.unwrap(currency)).transfer(address(manager), amount), "payment failed");
            require(manager.settle() == amount, "payment arrived short");
        } else if (delta > 0) {
            manager.take(currency, address(this), uint128(delta));
        }
    }
}

/// @dev Models only the constructor caller and its token movements; the real launch factory is external.
contract LaunchFactoryFixture is PoolActor {
    constructor(IPoolManager manager_) PoolActor(manager_) {}

    function deploy(bool tokenIsZero, address paired) external onlyController returns (SPALACEToken token) {
        bytes32 codeHash = keccak256(type(SPALACEToken).creationCode);
        for (uint256 i; i < 512; ++i) {
            bytes32 salt = bytes32(i);
            address predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, codeHash)))));
            if ((predicted < paired) == tokenIsZero && predicted != paired) {
                return new SPALACEToken{salt: salt}();
            }
        }
        revert("fixture salt search exhausted");
    }
}
