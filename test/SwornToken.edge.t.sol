// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {SwornToken} from "../src/SwornToken.sol";

/// @notice Edge cases and failure paths for SwornToken beyond the base suite: boundary amounts,
/// revert precedence, atomicity of failed calls, event exactness and the launch flows.
contract SwornTokenEdgeTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address constant FACTORY = address(0xFAC7);
    address constant DISTRIBUTOR = address(0xD157);
    address constant CLAIMANT = address(0xC1A1);
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant CAROL = address(0xCA201);

    SwornToken token;

    function setUp() public {
        vm.prank(FACTORY);
        token = new SwornToken();
    }

    // ---------------------------------------------------------------- supply and metadata

    function test_supplyIsExactlyOneBillionWholeTokens() public view {
        assertEq(token.totalSupply(), 1_000_000_000_000_000_000_000_000_000);
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
        assertEq(token.totalSupply() / 10 ** token.decimals(), 1_000_000_000);
        assertEq(token.totalSupply() % 10 ** token.decimals(), 0);
    }

    function test_eachDeploymentMintsOnlyToItsOwnDeployer() public {
        vm.prank(ALICE);
        SwornToken other = new SwornToken();
        assertEq(other.balanceOf(ALICE), SUPPLY);
        assertEq(other.balanceOf(FACTORY), 0);
        // The first token is untouched by the second deployment.
        assertEq(token.balanceOf(FACTORY), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_constructorEmitsExactlyOneEvent() public {
        vm.recordLogs();
        vm.prank(ALICE);
        SwornToken other = new SwornToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(other));
        assertEq(logs[0].topics[0], Transfer.selector);
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(ALICE))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_nonDeployerStartsWithNothing() public view {
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.allowance(FACTORY, ALICE), 0);
    }

    function test_rejectsEtherAndUnknownCalls() public {
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        (bool ok,) = address(token).call{value: 1}("");
        assertFalse(ok, "plain ether transfer accepted");
        vm.prank(ALICE);
        (ok,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", ALICE, SUPPLY));
        assertFalse(ok, "mint exists");
        vm.prank(FACTORY);
        (ok,) = address(token).call(abi.encodeWithSignature("burn(uint256)", 1));
        assertFalse(ok, "burn exists");
        vm.prank(FACTORY);
        (ok,) = address(token).call(abi.encodeWithSignature("burnFrom(address,uint256)", FACTORY, 1));
        assertFalse(ok, "burnFrom exists");
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(FACTORY), SUPPLY);
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ---------------------------------------------------------------- transfer boundaries

    function test_transferWholeSupply() public {
        vm.prank(FACTORY);
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(FACTORY), 0);
    }

    function test_RevertWhen_transferOneWeiMoreThanSupply() public {
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientBalance.selector, FACTORY, SUPPLY, SUPPLY + 1));
        vm.prank(FACTORY);
        token.transfer(ALICE, SUPPLY + 1);
    }

    function test_RevertWhen_transferMaxUint() public {
        vm.expectRevert(
            abi.encodeWithSelector(SwornToken.InsufficientBalance.selector, FACTORY, SUPPLY, type(uint256).max)
        );
        vm.prank(FACTORY);
        token.transfer(ALICE, type(uint256).max);
    }

    function test_RevertWhen_emptyAccountSendsOneWei() public {
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
    }

    function test_RevertWhen_transferZeroToZeroAddress() public {
        // The receiver check fires even for a zero amount.
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InvalidReceiver.selector, address(0)));
        vm.prank(ALICE);
        token.transfer(address(0), 0);
    }

    function test_RevertWhen_transferToZeroTakesPrecedenceOverBalance() public {
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InvalidReceiver.selector, address(0)));
        vm.prank(ALICE);
        token.transfer(address(0), 1);
    }

    function test_transferExactBalanceEmptiesSender() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, 7);
        vm.prank(ALICE);
        token.transfer(BOB, 7);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 7);
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
    }

    function test_transferWholeSupplyToSelf() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(FACTORY, FACTORY, SUPPLY);
        vm.prank(FACTORY);
        assertTrue(token.transfer(FACTORY, SUPPLY));
        assertEq(token.balanceOf(FACTORY), SUPPLY);
    }

    function test_RevertWhen_selfTransferExceedsBalance() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, 3);
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientBalance.selector, ALICE, 3, 4));
        vm.prank(ALICE);
        token.transfer(ALICE, 4);
        assertEq(token.balanceOf(ALICE), 3);
    }

    function test_transferToTokenContractIsAcceptedAndStuck() public {
        vm.prank(FACTORY);
        token.transfer(address(token), 10);
        assertEq(token.balanceOf(address(token)), 10);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
    }

    function test_roundTripRestoresBalances() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, 1234);
        vm.prank(ALICE);
        token.transfer(FACTORY, 1234);
        assertEq(token.balanceOf(FACTORY), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    // ---------------------------------------------------------------- approve

    function test_approveOverwritesBothWays() public {
        vm.startPrank(FACTORY);
        token.approve(ALICE, 100);
        token.approve(ALICE, 30);
        assertEq(token.allowance(FACTORY, ALICE), 30);
        token.approve(ALICE, 500);
        assertEq(token.allowance(FACTORY, ALICE), 500);
        token.approve(ALICE, 0);
        assertEq(token.allowance(FACTORY, ALICE), 0);
        vm.stopPrank();
    }

    function test_approveIsPerOwnerAndPerSpender() public {
        vm.prank(FACTORY);
        token.approve(ALICE, 11);
        assertEq(token.allowance(FACTORY, ALICE), 11);
        assertEq(token.allowance(ALICE, FACTORY), 0);
        assertEq(token.allowance(FACTORY, BOB), 0);
    }

    function test_approveWithoutBalanceAndAboveSupply() public {
        vm.prank(ALICE);
        assertTrue(token.approve(BOB, SUPPLY * 2));
        assertEq(token.allowance(ALICE, BOB), SUPPLY * 2);
    }

    function test_approveSelf() public {
        vm.prank(FACTORY);
        token.approve(FACTORY, 5);
        vm.prank(FACTORY);
        token.transferFrom(FACTORY, ALICE, 5);
        assertEq(token.allowance(FACTORY, FACTORY), 0);
        assertEq(token.balanceOf(ALICE), 5);
    }

    function test_RevertWhen_selfTransferFromWithoutSelfAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientAllowance.selector, FACTORY, 0, 1));
        vm.prank(FACTORY);
        token.transferFrom(FACTORY, ALICE, 1);
    }

    function test_RevertWhen_approveZeroSpenderWithZeroValue() public {
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InvalidSpender.selector, address(0)));
        vm.prank(ALICE);
        token.approve(address(0), 0);
    }

    function test_approveEmitsExactEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(ALICE, BOB, type(uint256).max);
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
    }

    // ---------------------------------------------------------------- transferFrom

    function test_transferFromExactAllowanceLeavesZero() public {
        vm.prank(FACTORY);
        token.approve(ALICE, 40);
        vm.prank(ALICE);
        token.transferFrom(FACTORY, BOB, 40);
        assertEq(token.allowance(FACTORY, ALICE), 0);
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(FACTORY, BOB, 1);
    }

    function test_transferFromInStepsSpendsAllowanceCumulatively() public {
        vm.prank(FACTORY);
        token.approve(ALICE, 10);
        vm.startPrank(ALICE);
        token.transferFrom(FACTORY, BOB, 4);
        token.transferFrom(FACTORY, CAROL, 6);
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientAllowance.selector, ALICE, 0, 1));
        token.transferFrom(FACTORY, BOB, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(BOB), 4);
        assertEq(token.balanceOf(CAROL), 6);
        assertEq(token.balanceOf(FACTORY), SUPPLY - 10);
    }

    function test_allowanceBelowMaxIsDecreased() public {
        uint256 almost = type(uint256).max - 1;
        vm.prank(FACTORY);
        token.approve(ALICE, almost);
        vm.prank(ALICE);
        token.transferFrom(FACTORY, BOB, 1);
        assertEq(token.allowance(FACTORY, ALICE), almost - 1);
    }

    function test_infiniteAllowanceCanMoveWholeSupplyAndEmitsNoApproval() public {
        vm.prank(FACTORY);
        token.approve(ALICE, type(uint256).max);
        vm.recordLogs();
        vm.prank(ALICE);
        token.transferFrom(FACTORY, BOB, SUPPLY);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], Transfer.selector);
        assertEq(token.allowance(FACTORY, ALICE), type(uint256).max);
        assertEq(token.balanceOf(BOB), SUPPLY);
    }

    function test_transferFromEmitsOnlyTransfer() public {
        vm.prank(FACTORY);
        token.approve(ALICE, 10);
        vm.recordLogs();
        vm.prank(ALICE);
        token.transferFrom(FACTORY, BOB, 3);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], Transfer.selector);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(FACTORY))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(BOB))));
        assertEq(abi.decode(logs[0].data, (uint256)), 3);
    }

    function test_RevertWhen_transferFromToZeroDoesNotSpendAllowance() public {
        vm.prank(FACTORY);
        token.approve(ALICE, 10);
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InvalidReceiver.selector, address(0)));
        vm.prank(ALICE);
        token.transferFrom(FACTORY, address(0), 5);
        assertEq(token.allowance(FACTORY, ALICE), 10);
        assertEq(token.balanceOf(FACTORY), SUPPLY);
    }

    function test_RevertWhen_transferFromBalanceShortDoesNotSpendAllowance() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, 5);
        vm.prank(ALICE);
        token.approve(BOB, 100);
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientBalance.selector, ALICE, 5, 6));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 6);
        assertEq(token.allowance(ALICE, BOB), 100);
        assertEq(token.balanceOf(ALICE), 5);
    }

    function test_RevertWhen_bothShort_allowanceErrorFirst() public {
        vm.prank(ALICE);
        token.approve(BOB, 2);
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientAllowance.selector, BOB, 2, 3));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 3);
    }

    function test_RevertWhen_infiniteAllowanceButBalanceShort() public {
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 1);
        assertEq(token.allowance(ALICE, BOB), type(uint256).max);
    }

    function test_RevertWhen_spenderUsesSomeoneElsesAllowance() public {
        vm.prank(FACTORY);
        token.approve(ALICE, 50);
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(FACTORY, BOB, 1);
        assertEq(token.allowance(FACTORY, ALICE), 50);
    }

    function test_RevertWhen_allowanceRevokedBeforeUse() public {
        vm.prank(FACTORY);
        token.approve(ALICE, 50);
        vm.prank(FACTORY);
        token.approve(ALICE, 0);
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(FACTORY, ALICE, 1);
    }

    function test_transferFromZeroValueWithoutAllowance() public {
        vm.prank(BOB);
        assertTrue(token.transferFrom(FACTORY, BOB, 0));
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(FACTORY), SUPPLY);
    }

    // ---------------------------------------------------------------- launch flows

    /// @dev The factory's 10% swarm share reaches the distributor whole and leaves it whole.
    function test_launchFlowsAreExact() public {
        uint256 swarm = (SUPPLY * 1_000) / 10_000;
        vm.prank(FACTORY);
        assertTrue(token.transfer(DISTRIBUTOR, swarm));
        assertEq(token.balanceOf(DISTRIBUTOR), swarm);

        // Claims of unequal sizes drain the distributor exactly.
        uint256 a = swarm / 3;
        uint256 b = swarm - a;
        vm.startPrank(DISTRIBUTOR);
        assertTrue(token.transfer(CLAIMANT, a));
        assertTrue(token.transfer(ALICE, b));
        vm.stopPrank();
        assertEq(token.balanceOf(DISTRIBUTOR), 0);
        assertEq(token.balanceOf(CLAIMANT), a);
        assertEq(token.balanceOf(ALICE), b);

        // Pool seed of 80% via transferFrom by a pool-manager-like spender.
        address manager = address(0x9001);
        uint256 seed = (SUPPLY * 8_000) / 10_000;
        vm.prank(FACTORY);
        token.approve(manager, seed);
        vm.prank(manager);
        assertTrue(token.transferFrom(FACTORY, manager, seed));
        assertEq(token.balanceOf(manager), seed);
        assertEq(token.balanceOf(FACTORY), SUPPLY - swarm - seed);
        assertEq(token.allowance(FACTORY, manager), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Nothing a privileged-looking call from the factory does can move a holder's balance.
    function test_factoryCannotMoveOrFreezeAHolder() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, 1000);
        vm.prank(FACTORY);
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientAllowance.selector, FACTORY, 0, 1));
        token.transferFrom(ALICE, FACTORY, 1);
        string[6] memory sigs = [
            "pause()", "freeze(address)", "blacklist(address)", "seize(address)", "lock(address)", "disableTransfers()"
        ];
        for (uint256 i; i < sigs.length; ++i) {
            vm.prank(FACTORY);
            (bool ok,) = address(token).call(abi.encodeWithSignature(sigs[i], ALICE));
            assertFalse(ok, sigs[i]);
        }
        assertEq(token.balanceOf(ALICE), 1000);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 1000));
        assertEq(token.balanceOf(BOB), 1000);
    }

    // ---------------------------------------------------------------- stateless fuzz

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferMovesExactly(uint256 seed, uint256 amount, uint256 sendBack) public {
        address to = address(uint160(bound(seed, 1, type(uint160).max)));
        amount = bound(amount, 0, SUPPLY);
        vm.prank(FACTORY);
        token.transfer(to, amount);
        if (to == FACTORY) {
            assertEq(token.balanceOf(FACTORY), SUPPLY);
            return;
        }
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(FACTORY), SUPPLY - amount);
        sendBack = bound(sendBack, 0, amount);
        vm.prank(to);
        token.transfer(FACTORY, sendBack);
        assertEq(token.balanceOf(to), amount - sendBack);
        assertEq(token.balanceOf(FACTORY), SUPPLY - amount + sendBack);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_RevertWhen_overBalance(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, type(uint256).max);
        vm.prank(FACTORY);
        token.transfer(ALICE, held);
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientBalance.selector, ALICE, held, amount));
        vm.prank(ALICE);
        token.transfer(BOB, amount);
        assertEq(token.balanceOf(ALICE), held);
        assertEq(token.balanceOf(BOB), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_RevertWhen_overAllowance(uint256 allowed, uint256 amount) public {
        allowed = bound(allowed, 0, type(uint256).max - 2);
        amount = bound(amount, allowed + 1, type(uint256).max);
        vm.prank(FACTORY);
        token.approve(ALICE, allowed);
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientAllowance.selector, ALICE, allowed, amount));
        vm.prank(ALICE);
        token.transferFrom(FACTORY, BOB, amount);
        assertEq(token.allowance(FACTORY, ALICE), allowed);
        assertEq(token.balanceOf(FACTORY), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveSetsExactly(uint256 seed, uint256 first, uint256 second) public {
        address spender = address(uint160(bound(seed, 1, type(uint160).max)));
        vm.startPrank(ALICE);
        token.approve(spender, first);
        assertEq(token.allowance(ALICE, spender), first);
        token.approve(spender, second);
        assertEq(token.allowance(ALICE, spender), second);
        vm.stopPrank();
    }
}
