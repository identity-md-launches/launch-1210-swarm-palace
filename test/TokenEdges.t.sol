// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SPALACEToken} from "../src/SPALACEToken.sol";
import {TestVm} from "./SPALACEToken.t.sol";

interface EdgeVm is TestVm {
    function deal(address account, uint256 balance) external;
    function warp(uint256 timestamp) external;
    function roll(uint256 blockNumber) external;
}

contract RejectingTokenReceiver {
    fallback() external {
        revert("receiver callback must not be called");
    }
}

contract TokenEdgesTest {
    EdgeVm private constant vm = EdgeVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant SUPPLY = 1e27;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    SPALACEToken private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new SPALACEToken();
    }

    function test_MaximumFiniteApprovalIsConsumedAndCanBeRevoked() public {
        require(token.approve(SPENDER, type(uint256).max - 1));
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, SUPPLY));
        require(token.allowance(address(this), SPENDER) == type(uint256).max - 1 - SUPPLY, "only max uint is infinite");
        require(token.balanceOf(ALICE) == SUPPLY, "whole supply delivered");
        require(token.approve(SPENDER, 0));
        require(token.allowance(address(this), SPENDER) == 0, "large approval revocable");
    }

    function test_RevokedUnlimitedApprovalCannotBeReused() public {
        token.transfer(ALICE, 9);
        vm.prank(ALICE);
        require(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        require(token.transferFrom(ALICE, BOB, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(ALICE, SPENDER, 0);
        vm.prank(ALICE);
        require(token.approve(SPENDER, 0));
        vm.expectRevert(abi.encodeWithSelector(SPALACEToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        require(token.balanceOf(ALICE) == 8 && token.balanceOf(BOB) == 1, "revoked spend changed balances");
        require(token.allowance(ALICE, SPENDER) == 0, "revoked spend restored authority");
    }

    function test_ApprovalsAreIsolatedByHolderAndSpender() public {
        token.transfer(ALICE, 100);
        token.approve(SPENDER, 12);
        vm.prank(ALICE);
        token.approve(SPENDER, 30);
        vm.prank(ALICE);
        token.approve(BOB, 40);
        vm.prank(SPENDER);
        require(token.transferFrom(ALICE, BOB, 7));
        require(token.allowance(ALICE, SPENDER) == 23, "spender allowance not consumed");
        require(token.allowance(ALICE, BOB) == 40, "other spender affected");
        require(token.allowance(address(this), SPENDER) == 12, "other holder affected");
        vm.prank(BOB);
        token.approve(SPENDER, type(uint256).max);
        require(token.allowance(ALICE, SPENDER) == 23, "stranger overwrote holder approval");
        vm.prank(ALICE);
        token.approve(SPENDER, 0);
        vm.prank(BOB);
        require(token.transferFrom(ALICE, BOB, 40));
        require(token.balanceOf(ALICE) == 53 && token.balanceOf(BOB) == 47, "independent spending");
    }

    function test_HolderAlsoNeedsApprovalToUseTransferFrom() public {
        token.transfer(ALICE, 1);
        vm.expectRevert(abi.encodeWithSelector(SPALACEToken.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(ALICE, BOB, 1);
        vm.prank(ALICE);
        token.approve(ALICE, 1);
        vm.prank(ALICE);
        require(token.transferFrom(ALICE, BOB, 1));
        require(token.allowance(ALICE, ALICE) == 0 && token.balanceOf(BOB) == 1, "self allowance semantics");
    }

    function test_SelfTransfersStillEnforceBalanceAndRollbackApproval() public {
        token.transfer(ALICE, 5);
        vm.expectRevert(abi.encodeWithSelector(SPALACEToken.ERC20InsufficientBalance.selector, ALICE, 5, 6));
        vm.prank(ALICE);
        token.transfer(ALICE, 6);
        vm.prank(ALICE);
        token.approve(SPENDER, 6);
        vm.expectRevert(abi.encodeWithSelector(SPALACEToken.ERC20InsufficientBalance.selector, ALICE, 5, 6));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, ALICE, 6);
        require(token.balanceOf(ALICE) == 5 && token.allowance(ALICE, SPENDER) == 6, "failed self transfer mutation");
    }

    function test_MaximumTransferRejectedEvenWithUnlimitedAllowance() public {
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                SPALACEToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        require(token.allowance(address(this), SPENDER) == type(uint256).max, "failed unlimited allowance changed");
        require(token.balanceOf(address(this)) == SUPPLY && token.balanceOf(ALICE) == 0, "maximum transfer mutation");
    }

    function test_RecipientCodeCannotBlockPlainTransfers() public {
        RejectingTokenReceiver receiver = new RejectingTokenReceiver();
        require(token.transfer(address(receiver), 1));
        token.approve(SPENDER, 2);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), address(receiver), 2));
        require(token.balanceOf(address(receiver)) == 3, "contract recipient did not receive full amount");
        // Sending tokens to the token contract is also an ordinary ERC-20 transfer, not a burn.
        require(token.transfer(address(token), 1));
        require(token.balanceOf(address(token)) == 1 && token.totalSupply() == SUPPLY, "self custody changed supply");
    }

    function test_NoTimeBasedInflationCooldownOrTransactionLimit() public {
        token.transfer(ALICE, SUPPLY);
        for (uint256 i; i < 5; ++i) {
            vm.prank(ALICE);
            require(token.transfer(BOB, SUPPLY));
            vm.prank(BOB);
            require(token.transfer(ALICE, SUPPLY));
        }
        vm.warp(block.timestamp + 3650 days);
        vm.roll(block.number + 25_000_000);
        vm.prank(ALICE);
        require(token.transfer(BOB, SUPPLY));
        require(
            token.balanceOf(BOB) == SUPPLY && token.totalSupply() == SUPPLY, "time changed supply or transfer rights"
        );
    }

    function test_NativeValueAndMalformedCallsCannotChangeTokenState() public {
        vm.deal(address(this), 1 ether);
        (bool receiveOk,) = address(token).call{value: 1}("");
        require(!receiveOk, "token unexpectedly accepted native currency");
        (bool payableApprove,) = address(token).call{value: 1}(abi.encodeCall(token.approve, (SPENDER, 1)));
        require(!payableApprove, "ERC20 approval unexpectedly payable");
        (bool truncated,) =
            address(token).call(abi.encodePacked(token.transfer.selector, bytes32(uint256(uint160(ALICE)))));
        require(!truncated, "truncated transfer accepted");
        (bool empty,) = address(token).call("");
        require(!empty, "unexpected fallback");
        require(address(token).balance == 0, "failed call retained ETH");
        require(token.allowance(address(this), SPENDER) == 0, "failed call approved spender");
        require(token.balanceOf(address(this)) == SUPPLY && token.balanceOf(ALICE) == 0, "failed call moved tokens");
    }

    function testFuzz_ZeroTransferFromPreservesAnyAllowance(uint256 allowance) public {
        require(token.approve(SPENDER, allowance));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 0);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, 0));
        require(token.allowance(address(this), SPENDER) == allowance, "zero spend consumed authority");
        require(token.balanceOf(address(this)) == SUPPLY && token.balanceOf(ALICE) == 0, "zero spend moved tokens");
    }

    function testFuzz_InvalidSpenderCannotChangeExistingApprovals(uint256 amount) public {
        token.approve(SPENDER, 7);
        vm.expectRevert(abi.encodeWithSelector(SPALACEToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), amount);
        require(token.allowance(address(this), address(0)) == 0, "invalid spender gained authority");
        require(token.allowance(address(this), SPENDER) == 7, "existing spender changed");
        require(token.balanceOf(address(this)) == SUPPLY, "invalid approval changed balance");
    }

    function testFuzz_AnyNonzeroRecipientReceivesExactAmount(address recipient, uint256 rawAmount) public {
        if (recipient == address(0)) recipient = ALICE;
        uint256 amount = rawAmount % (SUPPLY + 1);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), recipient, amount);
        require(token.transfer(recipient, amount));
        if (recipient == address(this)) {
            require(token.balanceOf(address(this)) == SUPPLY, "self transfer changed balance");
        } else {
            require(token.balanceOf(recipient) == amount, "recipient shorted");
            require(token.balanceOf(address(this)) == SUPPLY - amount, "sender charged fee");
        }
        require(token.totalSupply() == SUPPLY, "transfer changed supply");
    }
}
