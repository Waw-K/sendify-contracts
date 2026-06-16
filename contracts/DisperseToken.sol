// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title DisperseToken
 * @dev Contract for distributing ERC20 tokens or ETH to multiple wallets in batch
 */
contract DisperseToken is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Events
    event TokensDispersed(
        address indexed token,
        address indexed sender,
        uint256 totalAmount,
        uint256 recipientCount
    );
    
    event EtherDispersed(
        address indexed sender,
        uint256 totalAmount,
        uint256 recipientCount
    );

    // Errors
    error ArrayLengthMismatch();
    error InsufficientBalance();
    error TransferFailed();
    error ZeroAmount();
    error ZeroAddress();
    error ExceedsMaxRecipients();

    // Constants
    uint256 public constant MAX_RECIPIENTS = 200;
    uint256 public constant MIN_AMOUNT = 1;

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Distribute ERC20 tokens to multiple addresses
     */
    function disperseToken(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external nonReentrant whenNotPaused {
        if (token == address(0)) revert ZeroAddress();
        if (recipients.length != amounts.length) revert ArrayLengthMismatch();
        if (recipients.length == 0 || recipients.length > MAX_RECIPIENTS) {
            revert ExceedsMaxRecipients();
        }

        IERC20 tokenContract = IERC20(token);
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < amounts.length; ) {
            if (amounts[i] < MIN_AMOUNT) revert ZeroAmount();
            if (recipients[i] == address(0)) revert ZeroAddress();
            
            totalAmount += amounts[i];
            
            unchecked {
                ++i;
            }
        }

        tokenContract.safeTransferFrom(msg.sender, address(this), totalAmount);

        for (uint256 i = 0; i < recipients.length; ) {
            tokenContract.safeTransfer(recipients[i], amounts[i]);
            
            unchecked {
                ++i;
            }
        }

        emit TokensDispersed(token, msg.sender, totalAmount, recipients.length);
    }

    /**
     * @dev Distribute ETH to multiple addresses
     */
    function disperseEther(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external payable nonReentrant whenNotPaused {
        if (recipients.length != amounts.length) revert ArrayLengthMismatch();
        if (recipients.length == 0 || recipients.length > MAX_RECIPIENTS) {
            revert ExceedsMaxRecipients();
        }

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < amounts.length; ) {
            if (amounts[i] < MIN_AMOUNT) revert ZeroAmount();
            if (recipients[i] == address(0)) revert ZeroAddress();
            
            totalAmount += amounts[i];
            
            unchecked {
                ++i;
            }
        }

        if (msg.value < totalAmount) revert InsufficientBalance();

        for (uint256 i = 0; i < recipients.length; ) {
            (bool success, ) = recipients[i].call{value: amounts[i]}("");
            if (!success) revert TransferFailed();
            
            unchecked {
                ++i;
            }
        }

        uint256 surplus = msg.value - totalAmount;
        if (surplus > 0) {
            (bool success, ) = msg.sender.call{value: surplus}("");
            if (!success) revert TransferFailed();
        }

        emit EtherDispersed(msg.sender, totalAmount, recipients.length);
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {}
}