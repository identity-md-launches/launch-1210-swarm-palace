// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SPALACEToken} from "../src/SPALACEToken.sol";
import {TestVm} from "./SPALACEToken.t.sol";

/// @dev Bounds every action within a closed set of holders and records no shadow balances.
contract TransferHandler {
    TestVm private constant vm = TestVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    SPALACEToken public immutable token;
    address[4] private holders = [address(0x1001), address(0x1002), address(0x1003), address(0x1004)];

    constructor() {
        token = new SPALACEToken();
        token.transfer(holders[0], token.totalSupply());
    }

    function direct(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = holders[fromSeed % holders.length];
        address to = holders[toSeed % holders.length];
        uint256 amount = amountSeed % (token.balanceOf(from) + 1);
        vm.prank(from);
        require(token.transfer(to, amount));
    }

    function delegated(uint256 fromSeed, uint256 toSeed, uint256 amountSeed, bool infinite) external {
        address from = holders[fromSeed % holders.length];
        address to = holders[toSeed % holders.length];
        uint256 amount = amountSeed % (token.balanceOf(from) + 1);
        vm.prank(from);
        token.approve(address(this), infinite ? type(uint256).max : amount);
        require(token.transferFrom(from, to, amount));
        require(token.allowance(from, address(this)) == (infinite ? type(uint256).max : 0), "approval semantics");
    }

    function revoke(uint256 holderSeed) external {
        address holder = holders[holderSeed % holders.length];
        vm.prank(holder);
        token.approve(address(this), 0);
        require(token.allowance(holder, address(this)) == 0, "revocation");
    }

    function summedBalances() external view returns (uint256 total) {
        for (uint256 i; i < holders.length; ++i) {
            total += token.balanceOf(holders[i]);
        }
    }
}

contract ConservationTest {
    TransferHandler private handler;

    function setUp() public {
        handler = new TransferHandler();
    }

    /// @dev Foundry reads this targeting interface without requiring forge-std.
    function targetContracts() external view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_AllBalancesSumToFixedSupply() public view {
        SPALACEToken token = handler.token();
        require(token.totalSupply() == 1_000_000_000e18, "fixed supply");
        require(handler.summedBalances() == token.totalSupply(), "sum of balances must equal supply");
        require(token.balanceOf(address(handler)) == 0, "no fees collected");
        require(token.balanceOf(address(0)) == 0, "no burned supply");
    }
}
