// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title AffiliateVault
 * @dev Holds affiliate earnings. Anyone can deposit for an affiliate,
 *      and affiliates can withdraw their own balance at any time.
 */
contract AffiliateVault is ReentrancyGuard {
    mapping(address => uint256) public balances;

    event Deposited(address indexed affiliate, address indexed from, uint256 amount);
    event Withdrawn(address indexed affiliate, uint256 amount);

    /// @dev Deposit native tokens for an affiliate
    function deposit(address affiliate) external payable {
        require(msg.value > 0, "Zero deposit");
        require(affiliate != address(0), "Zero address");
        balances[affiliate] += msg.value;
        emit Deposited(affiliate, msg.sender, msg.value);
    }

    /// @dev Affiliate withdraws their full balance
    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "No balance");
        balances[msg.sender] = 0;
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Transfer failed");
        emit Withdrawn(msg.sender, amount);
    }

    /// @dev Check balance for any address
    function balanceOf(address affiliate) external view returns (uint256) {
        return balances[affiliate];
    }
}
