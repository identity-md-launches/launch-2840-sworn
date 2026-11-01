// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SwornToken} from "../src/SwornToken.sol";
import {DeploySworn} from "../script/DeploySworn.s.sol";

contract SwornTokenTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 constant SUPPLY = 1_000_000_000 ether;
    address constant DEPLOYER = address(0xFAC7);
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);

    SwornToken token;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new SwornToken();
    }

    function test_metadata() public view {
        assertEq(token.name(), "Sworn");
        assertEq(token.symbol(), "SWORN");
        assertEq(token.decimals(), 18);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), ALICE, SUPPLY);
        vm.prank(ALICE);
        new SwornToken();
    }

    function test_deployScriptDeploysToCaller() public {
        DeploySworn script = new DeploySworn();
        SwornToken t = script.deploy();
        assertEq(t.balanceOf(address(script)), SUPPLY);
        assertEq(t.totalSupply(), SUPPLY);
    }

    function test_transfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(DEPLOYER, ALICE, 100);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 100));
        assertEq(token.balanceOf(ALICE), 100);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 100);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(DEPLOYER, 5);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_transferZeroAmount() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_RevertWhen_transferExceedsBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10);
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientBalance.selector, ALICE, 10, 11));
        vm.prank(ALICE);
        token.transfer(BOB, 11);
    }

    function test_RevertWhen_transferToZero() public {
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InvalidReceiver.selector, address(0)));
        vm.prank(DEPLOYER);
        token.transfer(address(0), 1);
    }

    function test_approveAndTransferFrom() public {
        vm.expectEmit(true, true, false, true);
        emit Approval(DEPLOYER, ALICE, 50);
        vm.prank(DEPLOYER);
        assertTrue(token.approve(ALICE, 50));
        assertEq(token.allowance(DEPLOYER, ALICE), 50);

        vm.prank(ALICE);
        assertTrue(token.transferFrom(DEPLOYER, BOB, 30));
        assertEq(token.balanceOf(BOB), 30);
        assertEq(token.allowance(DEPLOYER, ALICE), 20);
    }

    function test_infiniteAllowanceNotDecreased() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, type(uint256).max);
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 1000);
        assertEq(token.allowance(DEPLOYER, ALICE), type(uint256).max);
        assertEq(token.balanceOf(BOB), 1000);
    }

    function test_RevertWhen_transferFromWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, ALICE, 1);
    }

    function test_RevertWhen_transferFromExceedsAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 5);
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientAllowance.selector, ALICE, 5, 6));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 6);
    }

    function test_RevertWhen_transferFromExceedsBalance() public {
        vm.prank(ALICE);
        token.approve(BOB, 100);
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 1);
    }

    function test_RevertWhen_approveZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(SwornToken.InvalidSpender.selector, address(0)));
        vm.prank(DEPLOYER);
        token.approve(address(0), 1);
    }

    function test_noPrivilegedCallsExist() public {
        string[8] memory sigs = [
            "mint(address,uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "pause()",
            "blacklist(address)",
            "transferOwnership(address)",
            "owner()",
            "initialize(address)"
        ];
        for (uint256 i; i < sigs.length; ++i) {
            vm.prank(DEPLOYER);
            (bool ok,) = address(token).call(abi.encodeWithSignature(sigs[i], ALICE, uint256(1)));
            assertFalse(ok, sigs[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != DEPLOYER);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(DEPLOYER);
        token.transfer(to, amount);
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(DEPLOYER) + token.balanceOf(to), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFrom(address spender, address to, uint256 allowed, uint256 amount) public {
        vm.assume(spender != address(0) && to != address(0) && to != DEPLOYER);
        allowed = bound(allowed, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(DEPLOYER);
        token.approve(spender, allowed);
        vm.prank(spender);
        if (amount > allowed) {
            vm.expectRevert(abi.encodeWithSelector(SwornToken.InsufficientAllowance.selector, spender, allowed, amount));
            token.transferFrom(DEPLOYER, to, amount);
        } else {
            token.transferFrom(DEPLOYER, to, amount);
            assertEq(token.balanceOf(to), amount);
            assertEq(token.allowance(DEPLOYER, spender), allowed == type(uint256).max ? allowed : allowed - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }
}
