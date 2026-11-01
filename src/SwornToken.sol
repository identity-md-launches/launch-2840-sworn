// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Sworn (SWORN)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 SWORN (18 decimals) is minted
/// once, in the constructor, to the deployer (`msg.sender`). There is no owner, no mint, no burn,
/// no pause, no blacklist and no fee: after deployment nobody holds any privilege over the token.
contract SwornToken {
    string public constant name = "Sworn";
    string public constant symbol = "SWORN";
    uint8 public constant decimals = 18;
    /// @notice 1,000,000,000 tokens in minor units.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    uint256 public immutable totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error InvalidReceiver(address receiver);
    error InvalidSpender(address spender);
    error InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    constructor() {
        totalSupply = TOTAL_SUPPLY;
        balanceOf[msg.sender] = TOTAL_SUPPLY;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        if (spender == address(0)) revert InvalidSpender(spender);
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /// @notice Moves `value` from `from` to `to` using the caller's allowance. An allowance of
    /// `type(uint256).max` is treated as infinite and is not decreased.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 current = allowance[from][msg.sender];
        if (current != type(uint256).max) {
            if (current < value) revert InsufficientAllowance(msg.sender, current, value);
            unchecked {
                allowance[from][msg.sender] = current - value;
            }
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) private {
        if (to == address(0)) revert InvalidReceiver(to);
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < value) revert InsufficientBalance(from, fromBalance, value);
        unchecked {
            balanceOf[from] = fromBalance - value;
            // Cannot overflow: the sum of all balances is the fixed total supply.
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }
}
