// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SPALACEToken} from "../src/SPALACEToken.sol";
import {TestVm} from "./SPALACEToken.t.sol";

/// @dev A closed actor set with an independent ledger. Approvals, revocations and
/// spends are separate actions, so authority persists across random call sequences.
contract TransferHandler {
    TestVm private constant vm = TestVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant SUPPLY = 1e27;
    SPALACEToken public immutable token;
    address[4] private holders =
        [address(0x1001), address(0x1002), address(0xD157), 0x000000000004444c5dc75cB358380D2e3dE08A90];
    mapping(address => uint256) private expectedBalances;
    mapping(address => mapping(address => uint256)) private expectedAllowances;

    constructor() {
        token = new SPALACEToken();
        for (uint256 i; i < holders.length; ++i) {
            require(token.transfer(holders[i], SUPPLY / holders.length));
            expectedBalances[holders[i]] = SUPPLY / holders.length;
        }
    }

    function direct(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _holder(fromSeed);
        address to = _holder(toSeed);
        uint256 amount = amountSeed % (expectedBalances[from] + 1);
        vm.prank(from);
        require(token.transfer(to, amount), "transfer returned false");
        _move(from, to, amount);
    }

    function approve(uint256 holderSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) external {
        address holder = _holder(holderSeed);
        address spender = _holder(spenderSeed);
        uint256 amount = mode % 4 == 0
            ? 0
            : mode % 4 == 1 ? type(uint256).max : mode % 4 == 2 ? type(uint256).max - 1 : amountSeed % (SUPPLY + 1);
        vm.prank(holder);
        require(token.approve(spender, amount), "approval returned false");
        expectedAllowances[holder][spender] = amount;
    }

    function delegated(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address from = _holder(fromSeed);
        address to = _holder(toSeed);
        address spender = _holder(spenderSeed);
        uint256 approved = expectedAllowances[from][spender];
        uint256 maximum = expectedBalances[from] < approved ? expectedBalances[from] : approved;
        uint256 amount = amountSeed % (maximum + 1);
        vm.prank(spender);
        require(token.transferFrom(from, to, amount), "delegated transfer returned false");
        if (approved != type(uint256).max) expectedAllowances[from][spender] -= amount;
        _move(from, to, amount);
    }

    function revoke(uint256 holderSeed, uint256 spenderSeed) external {
        address holder = _holder(holderSeed);
        address spender = _holder(spenderSeed);
        vm.prank(holder);
        require(token.approve(spender, 0), "revocation returned false");
        expectedAllowances[holder][spender] = 0;
    }

    function rejectOverBalance(uint256 fromSeed, uint256 toSeed, uint256 excessSeed) external {
        address from = _holder(fromSeed);
        uint256 balance = expectedBalances[from];
        uint256 requested = balance + 1 + excessSeed % (type(uint256).max - balance);
        vm.prank(from);
        (bool ok, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transfer, (_holder(toSeed), requested)));
        _assertRevert(
            ok, reason, abi.encodeWithSelector(SPALACEToken.ERC20InsufficientBalance.selector, from, balance, requested)
        );
    }

    function rejectOverspend(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed) external {
        address from = _holder(fromSeed);
        address spender = _holder(spenderSeed);
        uint256 approved = expectedAllowances[from][spender];
        uint256 balance = expectedBalances[from];
        uint256 requested = approved == type(uint256).max ? balance + 1 : approved + 1;
        bytes memory expected = approved == type(uint256).max
            ? abi.encodeWithSelector(SPALACEToken.ERC20InsufficientBalance.selector, from, balance, requested)
            : abi.encodeWithSelector(SPALACEToken.ERC20InsufficientAllowance.selector, spender, approved, requested);
        vm.prank(spender);
        (bool ok, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (from, _holder(toSeed), requested)));
        _assertRevert(ok, reason, expected);
    }

    function rejectZeroReceiver(uint256 holderSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address holder = _holder(holderSeed);
        address spender = _holder(spenderSeed);
        uint256 approved = expectedAllowances[holder][spender];
        uint256 maximum = expectedBalances[holder] < approved ? expectedBalances[holder] : approved;
        uint256 amount = amountSeed % (maximum + 1);
        vm.prank(spender);
        (bool ok, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (holder, address(0), amount)));
        _assertRevert(ok, reason, abi.encodeWithSelector(SPALACEToken.ERC20InvalidReceiver.selector, address(0)));
        // The model deliberately stays unchanged: even a consumed finite allowance must roll back.
    }

    function assertModel() external view {
        uint256 total;
        for (uint256 i; i < holders.length; ++i) {
            address holder = holders[i];
            uint256 actual = token.balanceOf(holder);
            require(actual == expectedBalances[holder], "holder balance diverged from independent ledger");
            total += actual;
            for (uint256 j; j < holders.length; ++j) {
                require(
                    token.allowance(holder, holders[j]) == expectedAllowances[holder][holders[j]],
                    "allowance diverged from independent ledger"
                );
            }
        }
        require(total == SUPPLY, "sum of balances must equal supply");
        require(token.totalSupply() == SUPPLY, "fixed supply");
        require(token.balanceOf(address(this)) == 0, "deployer collected a fee");
        require(token.balanceOf(address(token)) == 0, "token collected a fee");
        require(token.balanceOf(address(0)) == 0, "burned supply");
    }

    function _move(address from, address to, uint256 amount) private {
        expectedBalances[from] -= amount;
        expectedBalances[to] += amount;
    }

    function _holder(uint256 seed) private view returns (address) {
        return holders[seed % holders.length];
    }

    function _assertRevert(bool ok, bytes memory actual, bytes memory expected) private pure {
        require(!ok, "invalid action unexpectedly succeeded");
        require(keccak256(actual) == keccak256(expected), "invalid action reverted for wrong reason");
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

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_AllBalancesAndAllowancesMatchModel() public view {
        handler.assertModel();
    }
}
