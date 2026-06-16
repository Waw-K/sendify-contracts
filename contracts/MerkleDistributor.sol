// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MerkleDistributor is Ownable {
    using SafeERC20 for IERC20;

    // Distribution structure
    struct Distribution {
        address token;
        bytes32 merkleRoot;
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 expirationTime;
        bool expired;
        bool burnUnclaimed; // true = burn, false = reclaim
        string name;
        string proofsURL;
        address creator;
    }

    // Treasury for claim fees
    address public treasury;

    // Distributions mapping
    mapping(uint256 => Distribution) public distributions;
    uint256 public distributionCount;

    // Claims tracking
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    // Events
    event DistributionCreated(
        uint256 indexed distributionId,
        address indexed token,
        bytes32 merkleRoot,
        uint256 totalAmount,
        uint256 expirationTime,
        bool burnUnclaimed,
        string name,
        string proofsURL
    );

    event TokensClaimed(
        uint256 indexed distributionId,
        address indexed claimant,
        uint256 amount
    );

    event DistributionFinalized(
        uint256 indexed distributionId,
        uint256 claimedAmount,
        uint256 unclaimedAmount,
        bool burned
    );

    event TokensBurned(
        uint256 indexed distributionId,
        uint256 amount,
        uint256 timestamp
    );

    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    constructor() Ownable(msg.sender) {}

    /**
     * Set treasury address for claim fees
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        address old = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(old, _treasury);
    }

    /**
     * Create a new distribution
     */
function createDistribution(
    address token,
    bytes32 merkleRoot,
    uint256 totalAmount,
    uint256 claimDurationDays,
    bool burnUnclaimed,
    string memory name,
    string memory proofsURL
) external payable returns (uint256) {
    require(totalAmount > 0, "Amount must be > 0");
    require(claimDurationDays > 0, "Duration must be > 0");

    // Forward creation fee to treasury
    if (msg.value > 0) {
        require(treasury != address(0), "Treasury not set");
        (bool sent, ) = treasury.call{value: msg.value}("");
        require(sent, "Fee transfer failed");
    }

    // Transfer tokens to contract
    IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);

    uint256 distributionId = distributionCount++;
    uint256 expirationTime = block.timestamp + (claimDurationDays * 1 days);

    distributions[distributionId] = Distribution({
        token: token,
        merkleRoot: merkleRoot,
        totalAmount: totalAmount,
        claimedAmount: 0,
        expirationTime: expirationTime,
        expired: false,
        burnUnclaimed: burnUnclaimed,
        name: name,
        proofsURL: proofsURL,
        creator: msg.sender
    });

    emit DistributionCreated(
        distributionId,
        token,
        merkleRoot,
        totalAmount,
        expirationTime,
        burnUnclaimed,
        name,
        proofsURL
    );

    return distributionId;
}
    /**
     * Claim tokens
     */
    function claim(
        uint256 distributionId,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external payable {
        Distribution storage dist = distributions[distributionId];

        require(!dist.expired, "Distribution expired");
        require(block.timestamp < dist.expirationTime, "Claim period ended");
        require(!hasClaimed[distributionId][msg.sender], "Already claimed");

        // Forward claim fee to treasury
        if (msg.value > 0) {
            require(treasury != address(0), "Treasury not set");
            (bool sent, ) = treasury.call{value: msg.value}("");
            require(sent, "Fee transfer failed");
        }

        // Verify merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        require(
            MerkleProof.verify(merkleProof, dist.merkleRoot, leaf),
            "Invalid proof"
        );

        hasClaimed[distributionId][msg.sender] = true;
        dist.claimedAmount += amount;

        IERC20(dist.token).safeTransfer(msg.sender, amount);

        emit TokensClaimed(distributionId, msg.sender, amount);
    }

    /**
     * Finalize the distribution after expiration
     */
    function finalizeDistribution(uint256 distributionId) external {
        Distribution storage dist = distributions[distributionId];

        require(msg.sender == dist.creator || msg.sender == owner(), "Not authorized");
        require(!dist.expired, "Already finalized");
        require(block.timestamp >= dist.expirationTime, "Not expired yet");

        dist.expired = true;

        uint256 unclaimedAmount = dist.totalAmount - dist.claimedAmount;

        if (unclaimedAmount > 0) {
            if (dist.burnUnclaimed) {
                // Burn tokens (transfer to dead address)
                IERC20(dist.token).safeTransfer(
                    address(0x000000000000000000000000000000000000dEaD),
                    unclaimedAmount
                );

                emit TokensBurned(distributionId, unclaimedAmount, block.timestamp);
            } else {
                // Reclaim tokens
                IERC20(dist.token).safeTransfer(dist.creator, unclaimedAmount);
            }
        }

        emit DistributionFinalized(
            distributionId,
            dist.claimedAmount,
            unclaimedAmount,
            dist.burnUnclaimed
        );
    }

    /**
     * Check if an address can claim
     */
    function canClaim(
        uint256 distributionId,
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external view returns (bool) {
        Distribution storage dist = distributions[distributionId];

        if (dist.expired) return false;
        if (block.timestamp >= dist.expirationTime) return false;
        if (hasClaimed[distributionId][account]) return false;

        bytes32 leaf = keccak256(abi.encodePacked(account, amount));
        return MerkleProof.verify(merkleProof, dist.merkleRoot, leaf);
    }

    /**
     * Get distribution info
     */
    function getDistribution(uint256 distributionId)
        external
        view
        returns (Distribution memory)
    {
        return distributions[distributionId];
    }

    /**
     * Time remaining before expiration
     */
    function getTimeRemaining(uint256 distributionId)
        external
        view
        returns (uint256)
    {
        Distribution storage dist = distributions[distributionId];
        
        if (block.timestamp >= dist.expirationTime) {
            return 0;
        }
        
        return dist.expirationTime - block.timestamp;
    }
}