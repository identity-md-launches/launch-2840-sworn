// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SwornToken} from "../src/SwornToken.sol";

/// @notice Drives SwornToken with bounded random transfers, approvals and transferFroms between a
/// fixed set of actors, including calls that must fail, and keeps a ghost model of what every
/// balance and allowance should be.
contract SwornHandler is Test {
    SwornToken public immutable token;
    address[] public actors;
    /// @dev Every address that can ever hold tokens in this run: the actors plus the token itself.
    address[] public holders;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public ghostMoved;
    uint256 public calls;
    uint256 public okTransfers;
    uint256 public okTransferFroms;
    uint256 public expectedReverts;
    /// @dev Set if a call that the model says must fail succeeded, or one that must succeed failed.
    bool public modelBroken;

    constructor(SwornToken token_, address deployer, uint256 supply) {
        token = token_;
        actors.push(deployer);
        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA201));
        actors.push(address(0xD157));
        for (uint256 i; i < actors.length; ++i) {
            holders.push(actors[i]);
        }
        holders.push(address(token_));
        ghostBalance[deployer] = supply;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function holderCount() external view returns (uint256) {
        return holders.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _holder(uint256 seed) internal view returns (address) {
        return holders[seed % holders.length];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        calls++;
        address from = _actor(fromSeed);
        address to = _holder(toSeed);
        uint256 bal = ghostBalance[from];
        // Mostly in range; sometimes deliberately one past it.
        amount = bound(amount, 0, bal + 1);
        vm.prank(from);
        try token.transfer(to, amount) returns (bool ok) {
            if (!ok || amount > bal) modelBroken = true;
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            ghostMoved += amount;
            okTransfers++;
        } catch (bytes memory reason) {
            if (amount <= bal) modelBroken = true;
            if (
                keccak256(reason)
                    != keccak256(abi.encodeWithSelector(SwornToken.InsufficientBalance.selector, from, bal, amount))
            ) {
                modelBroken = true;
            }
            expectedReverts++;
        }
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        calls++;
        address from = _actor(fromSeed);
        amount = bound(amount, 0, ghostBalance[from]);
        vm.prank(from);
        try token.transfer(address(0), amount) {
            modelBroken = true;
        } catch {
            expectedReverts++;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool infinite) external {
        calls++;
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (infinite) amount = type(uint256).max;
        else amount = bound(amount, 0, ghostBalance[owner] + 2);
        vm.prank(owner);
        try token.approve(spender, amount) returns (bool ok) {
            if (!ok) modelBroken = true;
            ghostAllowance[owner][spender] = amount;
        } catch {
            modelBroken = true;
        }
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        calls++;
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _holder(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        uint256 bal = ghostBalance[from];
        uint256 cap = allowed == type(uint256).max ? bal : (allowed < bal ? allowed : bal);
        amount = bound(amount, 0, cap + 1);
        bool shouldPass = amount <= bal && (allowed == type(uint256).max || amount <= allowed);
        vm.prank(spender);
        try token.transferFrom(from, to, amount) returns (bool ok) {
            if (!ok || !shouldPass) modelBroken = true;
            if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            ghostMoved += amount;
            okTransferFroms++;
        } catch {
            if (shouldPass) modelBroken = true;
            expectedReverts++;
        }
    }
}

contract SwornTokenInvariantTest is Test {
    uint256 constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address constant DEPLOYER = address(0xFAC7);

    SwornToken token;
    SwornHandler handler;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new SwornToken();
        handler = new SwornHandler(token, DEPLOYER, SUPPLY);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = SwornHandler.transfer.selector;
        selectors[1] = SwornHandler.transferToZero.selector;
        selectors[2] = SwornHandler.approve.selector;
        selectors[3] = SwornHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_totalSupplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        uint256 n = handler.holderCount();
        for (uint256 i; i < n; ++i) {
            sum += token.balanceOf(handler.holders(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesAndAllowancesMatchModel() public view {
        assertFalse(handler.modelBroken(), "a call succeeded or failed against the model");
        uint256 n = handler.holderCount();
        for (uint256 i; i < n; ++i) {
            address h = handler.holders(i);
            assertEq(token.balanceOf(h), handler.ghostBalance(h));
        }
        uint256 a = handler.actorCount();
        for (uint256 i; i < a; ++i) {
            for (uint256 j; j < a; ++j) {
                address o = handler.actors(i);
                address s = handler.actors(j);
                assertEq(token.allowance(o, s), handler.ghostAllowance(o, s));
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_metadataIsConstant() public view {
        assertEq(token.name(), "Sworn");
        assertEq(token.symbol(), "SWORN");
        assertEq(token.decimals(), 18);
    }

    /// @dev Guards against a vacuous run: once calls were made, some must have moved value.
    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_handlerExercisesTheToken() public view {
        if (handler.calls() >= 20) {
            assertGt(handler.okTransfers() + handler.okTransferFroms(), 0, "no call ever moved tokens");
        }
    }
}
