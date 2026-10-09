// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Swarm Palace
/// @notice A fixed-supply, fee-free ERC-20 with no administrative interface.
/// @dev The constructor credits the entire supply to its caller. The launch factory,
/// not this token, distributes the swarm allocation and seeds the pool.
contract SPALACEToken {
    string public constant name = "Swarm Palace";
    string public constant symbol = "SPALACE";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_000_000_000 * 10 ** 18;

    mapping(address account => uint256 amount) public balanceOf;
    mapping(address holder => mapping(address spender => uint256 amount)) public allowance;

    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidSpender(address spender);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /// @dev Maximum uint256 is an unlimited approval; finite approvals are consumed.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 approved = allowance[from][msg.sender];
        if (approved != type(uint256).max) {
            if (approved < value) revert ERC20InsufficientAllowance(msg.sender, approved, value);
            unchecked {
                allowance[from][msg.sender] = approved - value;
            }
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) private {
        if (from == address(0)) revert ERC20InvalidSender(address(0));
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        uint256 balance = balanceOf[from];
        if (balance < value) revert ERC20InsufficientBalance(from, balance, value);
        unchecked {
            balanceOf[from] = balance - value;
            // All balances sum to 1e27, so this cannot overflow. Reading after
            // subtraction also preserves the balance for a transfer to oneself.
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }
}
