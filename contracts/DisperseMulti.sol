// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title DisperseMulti
 * @dev Distributes native tokens + multiple ERC20s to multiple wallets in one transaction.
 *      ERC20 approvals must be done before calling this function.
 */
contract DisperseMulti is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    event MultiDispersed(
        address indexed sender,
        uint256 tokenCount,
        uint256 totalRecipients
    );

    event FeePaid(
        address indexed payer,
        address indexed feeRecipient,
        uint256 feeAmount
    );

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

    error ArrayLengthMismatch();
    error InsufficientNativeValue();
    error TransferFailed();
    error ZeroAmount();
    error ZeroAddress();
    error ExceedsMaxRecipients();
    error EmptyTokenList();

    uint256 public constant MAX_RECIPIENTS = 200;
    uint256 public constant MIN_AMOUNT = 1;

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Distributes native + multiple ERC20 tokens in one transaction.
     * @param tokens   Token addresses; use address(0) for native ETH/BNB/AVAX/POL.
     * @param recipients 2D array — recipients[i] is the list of recipients for tokens[i].
     * @param amounts    2D array — amounts[i][j] is the amount for recipients[i][j].
     *
     * Requirements:
     * - msg.value must cover the exact total native amount (surplus is refunded).
     * - Caller must have approved this contract for each ERC20 token beforehand.
     */
    function disperseMulti(
        address[] calldata tokens,
        address[][] calldata recipients,
        uint256[][] calldata amounts
    ) external payable nonReentrant whenNotPaused {
        uint256 tokenCount = tokens.length;
        if (tokenCount == 0) revert EmptyTokenList();
        if (recipients.length != tokenCount || amounts.length != tokenCount) revert ArrayLengthMismatch();

        // ── First pass: validate inputs and compute totals ──────────────────
        uint256[] memory tokenTotals = new uint256[](tokenCount);
        uint256 nativeRequired = 0;
        uint256 totalRecipients = 0;

        for (uint256 i = 0; i < tokenCount; ) {
            uint256 recipientCount = recipients[i].length;
            if (recipientCount == 0 || recipientCount > MAX_RECIPIENTS) revert ExceedsMaxRecipients();
            if (amounts[i].length != recipientCount) revert ArrayLengthMismatch();

            uint256 tokenTotal = 0;
            for (uint256 j = 0; j < recipientCount; ) {
                if (amounts[i][j] < MIN_AMOUNT) revert ZeroAmount();
                if (recipients[i][j] == address(0)) revert ZeroAddress();
                tokenTotal += amounts[i][j];
                unchecked { ++j; }
            }

            tokenTotals[i] = tokenTotal;

            if (tokens[i] == address(0)) {
                nativeRequired += tokenTotal;
            }

            totalRecipients += recipientCount;
            unchecked { ++i; }
        }

        if (msg.value < nativeRequired) revert InsufficientNativeValue();

        // ── Second pass: execute distributions ──────────────────────────────
        for (uint256 i = 0; i < tokenCount; ) {
            if (tokens[i] == address(0)) {
                // Native token distribution
                for (uint256 j = 0; j < recipients[i].length; ) {
                    (bool success, ) = recipients[i][j].call{value: amounts[i][j]}("");
                    if (!success) revert TransferFailed();
                    unchecked { ++j; }
                }
            } else {
                // ERC20 distribution — pull from sender then push to each recipient
                IERC20 token = IERC20(tokens[i]);
                token.safeTransferFrom(msg.sender, address(this), tokenTotals[i]);
                for (uint256 j = 0; j < recipients[i].length; ) {
                    token.safeTransfer(recipients[i][j], amounts[i][j]);
                    unchecked { ++j; }
                }
            }
            unchecked { ++i; }
        }

        // ── Refund surplus native value ──────────────────────────────────────
        uint256 surplus = msg.value - nativeRequired;
        if (surplus > 0) {
            (bool success, ) = msg.sender.call{value: surplus}("");
            if (!success) revert TransferFailed();
        }

        emit MultiDispersed(msg.sender, tokenCount, totalRecipients);
    }

    /**
     * @dev Distributes tokens, pays platform fee to treasury, and deposits affiliate share into vault.
     * @param tokens       Token addresses; use address(0) for native.
     * @param recipients   2D array of recipients per token.
     * @param amounts      2D array of amounts per recipient.
     * @param feeRecipient Treasury address.
     * @param feeAmount    Fee to treasury in native currency (wei).
     * @param affiliateVault  AffiliateVault contract address (address(0) to skip).
     * @param affiliateWallet Affiliate wallet to credit in the vault.
     * @param affiliateAmount Affiliate share in wei.
     *
     * msg.value must cover feeAmount + affiliateAmount + total native distribution.
     */
    function disperse(
        address[] calldata tokens,
        address[][] calldata recipients,
        uint256[][] calldata amounts,
        address payable feeRecipient,
        uint256 feeAmount,
        address affiliateVault,
        address affiliateWallet,
        uint256 affiliateAmount
    ) external payable nonReentrant whenNotPaused {
        // ── Pay fee to treasury ──────────────────────────────────────────────
        if (feeAmount > 0 && feeRecipient != address(0)) {
            (bool feeSent, ) = feeRecipient.call{value: feeAmount}("");
            if (!feeSent) revert TransferFailed();
            emit FeePaid(msg.sender, feeRecipient, feeAmount);
        }

        // ── Deposit affiliate share into vault ───────────────────────────────
        if (affiliateAmount > 0 && affiliateVault != address(0) && affiliateWallet != address(0)) {
            (bool vaultSent, ) = affiliateVault.call{value: affiliateAmount}(
                abi.encodeWithSignature("deposit(address)", affiliateWallet)
            );
            if (!vaultSent) revert TransferFailed();
        }

        // ── Distribute tokens (same logic as disperseMulti) ──────────────────
        uint256 tokenCount = tokens.length;
        if (tokenCount == 0) revert EmptyTokenList();
        if (recipients.length != tokenCount || amounts.length != tokenCount) revert ArrayLengthMismatch();

        uint256[] memory tokenTotals = new uint256[](tokenCount);
        uint256 nativeRequired = 0;
        uint256 totalRecipients = 0;

        for (uint256 i = 0; i < tokenCount; ) {
            uint256 recipientCount = recipients[i].length;
            if (recipientCount == 0 || recipientCount > MAX_RECIPIENTS) revert ExceedsMaxRecipients();
            if (amounts[i].length != recipientCount) revert ArrayLengthMismatch();

            uint256 tokenTotal = 0;
            for (uint256 j = 0; j < recipientCount; ) {
                if (amounts[i][j] < MIN_AMOUNT) revert ZeroAmount();
                if (recipients[i][j] == address(0)) revert ZeroAddress();
                tokenTotal += amounts[i][j];
                unchecked { ++j; }
            }

            tokenTotals[i] = tokenTotal;
            if (tokens[i] == address(0)) {
                nativeRequired += tokenTotal;
            }
            totalRecipients += recipientCount;
            unchecked { ++i; }
        }

        if (msg.value < feeAmount + affiliateAmount + nativeRequired) revert InsufficientNativeValue();

        for (uint256 i = 0; i < tokenCount; ) {
            if (tokens[i] == address(0)) {
                for (uint256 j = 0; j < recipients[i].length; ) {
                    (bool success, ) = recipients[i][j].call{value: amounts[i][j]}("");
                    if (!success) revert TransferFailed();
                    unchecked { ++j; }
                }
            } else {
                IERC20 token = IERC20(tokens[i]);
                token.safeTransferFrom(msg.sender, address(this), tokenTotals[i]);
                for (uint256 j = 0; j < recipients[i].length; ) {
                    token.safeTransfer(recipients[i][j], amounts[i][j]);
                    unchecked { ++j; }
                }
            }
            unchecked { ++i; }
        }

        // ── Refund surplus ───────────────────────────────────────────────────
        uint256 surplus = msg.value - feeAmount - affiliateAmount - nativeRequired;
        if (surplus > 0) {
            (bool success, ) = msg.sender.call{value: surplus}("");
            if (!success) revert TransferFailed();
        }

        emit MultiDispersed(msg.sender, tokenCount, totalRecipients);
    }

    /**
     * @dev Backwards-compatible: distribute a single ERC20 token
     */
    function disperseToken(
        address token,
        address[] calldata _recipients,
        uint256[] calldata _amounts
    ) external nonReentrant whenNotPaused {
        if (token == address(0)) revert ZeroAddress();
        if (_recipients.length != _amounts.length) revert ArrayLengthMismatch();
        if (_recipients.length == 0 || _recipients.length > MAX_RECIPIENTS) revert ExceedsMaxRecipients();

        IERC20 tokenContract = IERC20(token);
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < _amounts.length; ) {
            if (_amounts[i] < MIN_AMOUNT) revert ZeroAmount();
            if (_recipients[i] == address(0)) revert ZeroAddress();
            totalAmount += _amounts[i];
            unchecked { ++i; }
        }

        tokenContract.safeTransferFrom(msg.sender, address(this), totalAmount);

        for (uint256 i = 0; i < _recipients.length; ) {
            tokenContract.safeTransfer(_recipients[i], _amounts[i]);
            unchecked { ++i; }
        }

        emit TokensDispersed(token, msg.sender, totalAmount, _recipients.length);
    }

    /**
     * @dev Backwards-compatible: distribute native ETH/BNB/AVAX/POL
     */
    function disperseEther(
        address[] calldata _recipients,
        uint256[] calldata _amounts
    ) external payable nonReentrant whenNotPaused {
        if (_recipients.length != _amounts.length) revert ArrayLengthMismatch();
        if (_recipients.length == 0 || _recipients.length > MAX_RECIPIENTS) revert ExceedsMaxRecipients();

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < _amounts.length; ) {
            if (_amounts[i] < MIN_AMOUNT) revert ZeroAmount();
            if (_recipients[i] == address(0)) revert ZeroAddress();
            totalAmount += _amounts[i];
            unchecked { ++i; }
        }

        if (msg.value < totalAmount) revert InsufficientNativeValue();

        for (uint256 i = 0; i < _recipients.length; ) {
            (bool success, ) = _recipients[i].call{value: _amounts[i]}("");
            if (!success) revert TransferFailed();
            unchecked { ++i; }
        }

        uint256 surplus = msg.value - totalAmount;
        if (surplus > 0) {
            (bool success, ) = msg.sender.call{value: surplus}("");
            if (!success) revert TransferFailed();
        }

        emit EtherDispersed(msg.sender, totalAmount, _recipients.length);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {}
}
