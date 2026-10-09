// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SPALACEToken} from "../src/SPALACEToken.sol";

interface TestVm {
    function prank(address caller) external;
    function expectRevert(bytes calldata data) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
}

contract TokenFactoryProbe {
    function deploy() external returns (SPALACEToken) {
        return new SPALACEToken();
    }

    function move(SPALACEToken token, address to, uint256 value) external {
        require(token.transfer(to, value));
    }
}

contract SPALACETokenTest {
    TestVm private constant vm = TestVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant SUPPLY = 1_000_000_000e18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    address private constant DISTRIBUTOR = address(0xD157);
    address private constant MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    SPALACEToken private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new SPALACEToken();
    }

    function test_LaunchIdentityAndWholeSupplyToConstructorCaller() public view {
        require(keccak256(bytes(token.name())) == keccak256("Swarm Palace"), "name");
        require(keccak256(bytes(token.symbol())) == keccak256("SPALACE"), "symbol");
        require(token.decimals() == 18, "decimals");
        require(token.totalSupply() == SUPPLY, "supply");
        require(token.balanceOf(address(this)) == SUPPLY, "deployer allocation");
        require(token.balanceOf(address(token)) == 0, "no token reserve");
        require(token.balanceOf(address(0)) == 0, "no zero allocation");
    }

    function test_ConstructorEmitsWholeSupplyMintToFactory() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(factory), SUPPLY);
        SPALACEToken launched = factory.deploy();
        require(launched.totalSupply() == SUPPLY, "mint matches declared supply");
        require(launched.balanceOf(address(factory)) == SUPPLY, "factory receives all minted units");
    }

    function test_FactoryReceivesFullSupplyAndControlsDistribution() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        SPALACEToken launched = factory.deploy();
        require(launched.balanceOf(address(factory)) == SUPPLY, "factory must receive 100%");
        require(launched.balanceOf(address(this)) == 0, "not tx.origin or requester");
        factory.move(launched, DISTRIBUTOR, SUPPLY / 10);
        factory.move(launched, MANAGER, SUPPLY * 9 / 10);
        require(launched.balanceOf(address(factory)) == 0, "distribution complete");
        require(launched.balanceOf(DISTRIBUTOR) == SUPPLY / 10, "swarm arrives whole");
        require(launched.balanceOf(MANAGER) == SUPPLY * 9 / 10, "seed arrives whole");
        vm.prank(DISTRIBUTOR);
        require(launched.transfer(ALICE, SUPPLY / 10));
        vm.prank(MANAGER);
        require(launched.transfer(BOB, 123e18));
        vm.prank(BOB);
        require(launched.transfer(MANAGER, 123e18));
        require(launched.balanceOf(ALICE) == SUPPLY / 10, "claim arrives whole");
        require(launched.balanceOf(MANAGER) == SUPPLY * 9 / 10, "buy/sell token leg");
        require(launched.totalSupply() == SUPPLY, "fixed supply after launch");
    }

    function test_TransferAndApprovalEvents() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 1);
        require(token.transfer(ALICE, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 2);
        require(token.approve(SPENDER, 2));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), BOB, 2);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), BOB, 2));
    }

    function test_ZeroValueTransfersEmitEvents() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        require(token.transfer(BOB, 0));

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        require(token.transferFrom(ALICE, BOB, 0));

        require(token.balanceOf(address(this)) == SUPPLY, "zero transfers preserve allocation");
        require(token.balanceOf(ALICE) == 0 && token.balanceOf(BOB) == 0, "zero transfers create no balance");
        require(token.allowance(ALICE, SPENDER) == 0, "zero transfer needs no allowance");
    }

    function test_ZeroTransfersAndEntireBalance() public {
        vm.prank(ALICE);
        require(token.transfer(BOB, 0));
        vm.prank(SPENDER);
        require(token.transferFrom(ALICE, BOB, 0));
        require(token.transfer(ALICE, SUPPLY));
        vm.prank(ALICE);
        require(token.transfer(BOB, SUPPLY));
        require(token.balanceOf(BOB) == SUPPLY, "no tax or limit");
        require(token.balanceOf(address(this)) == 0 && token.balanceOf(ALICE) == 0, "no residue");
    }

    function test_TransferToZeroCannotBurnSupply() public {
        vm.expectRevert(abi.encodeWithSelector(SPALACEToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        require(token.balanceOf(address(this)) == SUPPLY, "balance rolled back");
        require(token.totalSupply() == SUPPLY, "no burn");
    }

    function test_ZeroValueToZeroAlsoReverts() public {
        vm.expectRevert(abi.encodeWithSelector(SPALACEToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_ZeroSenderRejected() public {
        vm.expectRevert(abi.encodeWithSelector(SPALACEToken.ERC20InvalidSender.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_ZeroSpenderRejected() public {
        vm.expectRevert(abi.encodeWithSelector(SPALACEToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_InsufficientBalanceRollsBack() public {
        vm.expectRevert(
            abi.encodeWithSelector(SPALACEToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(ALICE, SUPPLY + 1);
        require(token.balanceOf(address(this)) == SUPPLY && token.balanceOf(ALICE) == 0, "rollback");
    }

    function test_ApprovalOverwriteAndRevocation() public {
        token.approve(SPENDER, 100);
        token.approve(SPENDER, 7);
        require(token.allowance(address(this), SPENDER) == 7, "approval replaces rather than adds");
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(SPALACEToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
    }

    function test_FailedTransferFromRestoresSpentAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSelector(SPALACEToken.ERC20InsufficientBalance.selector, ALICE, 0, 100));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 100);
        require(token.allowance(ALICE, SPENDER) == 100, "allowance rollback");
        require(token.balanceOf(BOB) == 0, "balance rollback");
    }

    function test_TransferFromToZeroRestoresAllowance() public {
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSelector(SPALACEToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 100);
        require(token.allowance(address(this), SPENDER) == 100, "allowance rollback");
        require(token.balanceOf(address(this)) == SUPPLY, "balance rollback");
    }

    function test_DeployerCannotTakeHolderFundsWithoutApproval() public {
        token.transfer(ALICE, 100);
        vm.expectRevert(abi.encodeWithSelector(SPALACEToken.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        require(token.balanceOf(ALICE) == 100, "no deployer privilege");
        vm.prank(ALICE);
        token.transfer(BOB, 100);
        require(token.balanceOf(BOB) == 100, "holder remains free");
    }

    function test_NoMintBurnOrAdminInterface() public {
        token.transfer(ALICE, 100);
        // Correct argument types matter: an invalid bool could make an existing
        // privileged function revert in ABI decoding and hide that interface.
        bytes[] memory calls = new bytes[](30);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", ALICE, 100);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 100);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 100);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 100);
        calls[5] = abi.encodeWithSignature("owner()");
        calls[6] = abi.encodeWithSignature("setOwner(address)", ALICE);
        calls[7] = abi.encodeWithSignature("transferOwnership(address)", ALICE);
        calls[8] = abi.encodeWithSignature("upgradeTo(address)", ALICE);
        calls[9] = abi.encodeWithSignature("initialize(address)", ALICE);
        calls[10] = abi.encodeWithSignature("setMinter(address)", ALICE);
        calls[11] = abi.encodeWithSignature("pause()");
        calls[12] = abi.encodeWithSignature("unpause()");
        calls[13] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[14] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[15] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[16] = abi.encodeWithSignature("setFee(uint256)", 100);
        calls[17] = abi.encodeWithSignature("issue(uint256)", 100);
        calls[18] = abi.encodeWithSignature("blocklist(address)", ALICE);
        calls[19] = abi.encodeWithSignature("freezeAccount(address)", ALICE);
        calls[20] = abi.encodeWithSignature("setBlacklist(address,bool)", ALICE, true);
        calls[21] = abi.encodeWithSignature("setBlocked(address,bool)", ALICE, true);
        calls[22] = abi.encodeWithSignature("lock(address)", ALICE);
        calls[23] = abi.encodeWithSignature("disableTransfers()");
        calls[24] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[25] = abi.encodeWithSignature("renounceOwnership()");
        calls[26] = abi.encodeWithSignature("grantRole(bytes32,address)", bytes32(0), ALICE);
        calls[27] = abi.encodeWithSignature("setMaxTxAmount(uint256)", 0);
        calls[28] = abi.encodeWithSignature("setTax(uint256)", 100);
        calls[29] = abi.encodeWithSignature("initialize()");
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerOk,) = address(token).call(calls[i]);
            require(!deployerOk, "unexpected deployer admin interface");
            vm.prank(BOB);
            (bool strangerOk,) = address(token).call(calls[i]);
            require(!strangerOk, "unexpected public admin interface");
        }
        require(token.totalSupply() == SUPPLY, "supply immutable");
        require(token.balanceOf(ALICE) == 100, "holder funds immutable to admin calls");
        vm.prank(ALICE);
        token.transfer(BOB, 100);
        require(token.balanceOf(BOB) == 100, "cannot freeze holder");
    }

    function test_ForbiddenOpcodesAbsent() public view {
        bytes memory runtime = address(token).code;
        require(runtime.length > 0 && runtime.length <= 24_576, "runtime size");
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            require(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }

    function testFuzz_TransferRoundTripPreservesAllSupply(uint256 rawAmount) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        token.transfer(ALICE, amount);
        vm.prank(ALICE);
        token.transfer(BOB, amount);
        vm.prank(BOB);
        token.transfer(address(this), amount);
        require(token.balanceOf(address(this)) == SUPPLY, "round trip loses value");
        require(token.balanceOf(ALICE) == 0 && token.balanceOf(BOB) == 0, "no fees retained");
        require(token.totalSupply() == SUPPLY, "supply conserved");
    }

    function testFuzz_SelfTransferConservesBalance(uint256 rawAmount) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        token.transfer(address(this), amount);
        require(token.balanceOf(address(this)) == SUPPLY, "self transfer changes funds");
        token.approve(SPENDER, amount);
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(this), amount);
        require(token.balanceOf(address(this)) == SUPPLY, "delegated self transfer changes funds");
        require(token.allowance(address(this), SPENDER) == 0, "finite approval consumed");
    }

    function testFuzz_FiniteAllowanceEnforcesCumulativeLimit(uint256 rawApproval, uint256 rawSpend) public {
        uint256 approved = rawApproval % (SUPPLY + 1);
        uint256 spend = rawSpend % (approved + 1);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, spend);
        uint256 left = approved - spend;
        require(token.allowance(address(this), SPENDER) == left, "remaining allowance");
        vm.expectRevert(
            abi.encodeWithSelector(SPALACEToken.ERC20InsufficientAllowance.selector, SPENDER, left, left + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, left + 1);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, left);
        require(token.allowance(address(this), SPENDER) == 0, "approval exhausted");
        require(token.balanceOf(ALICE) == approved, "exact approved amount delivered");
    }

    function testFuzz_UnlimitedApprovalPersists(uint256 rawAmount) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, amount);
        vm.prank(ALICE);
        token.transfer(address(this), amount);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, amount);
        require(token.allowance(address(this), SPENDER) == type(uint256).max, "unlimited approval persists");
        require(token.balanceOf(ALICE) + token.balanceOf(address(this)) == SUPPLY, "conservation");
    }

    function testFuzz_TransferAboveBalanceNeverMutates(uint256 rawBalance, uint256 rawExcess) public {
        uint256 balance = rawBalance % (SUPPLY + 1);
        uint256 excess = 1 + rawExcess % (type(uint256).max - balance);
        uint256 requested = balance + excess;
        token.transfer(ALICE, balance);
        vm.expectRevert(
            abi.encodeWithSelector(SPALACEToken.ERC20InsufficientBalance.selector, ALICE, balance, requested)
        );
        vm.prank(ALICE);
        token.transfer(BOB, requested);
        require(token.balanceOf(ALICE) == balance && token.balanceOf(BOB) == 0, "failed transfer mutation");
        require(token.totalSupply() == SUPPLY, "fixed supply");
    }
}
