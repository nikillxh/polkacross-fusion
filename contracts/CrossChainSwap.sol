// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract CrossChainSwap is ReentrancyGuard {
    using ECDSA for bytes32;

    struct Swap {
        address initiator;
        address participant;
        uint256 amount;
        bytes32 hashlock;
        uint256 timelock;
        bool withdrawn;
        bool refunded;
        string polkadotAddress; // Destination address on Polkadot
    }

    mapping(bytes32 => Swap) public swaps;
    
    // Events
    event SwapInitiated(
        bytes32 indexed swapId,
        address indexed initiator,
        address indexed participant,
        uint256 amount,
        bytes32 hashlock,
        uint256 timelock,
        string polkadotAddress
    );
    
    event SwapWithdrawn(bytes32 indexed swapId, bytes32 preimage);
    event SwapRefunded(bytes32 indexed swapId);

    // Minimum timelock duration (1 hour)
    uint256 public constant MIN_TIMELOCK = 3600;
    
    modifier swapExists(bytes32 _swapId) {
        require(swaps[_swapId].initiator != address(0), "Swap does not exist");
        _;
    }
    
    modifier withdrawable(bytes32 _swapId, bytes32 _preimage) {
        require(swaps[_swapId].hashlock == keccak256(abi.encodePacked(_preimage)), "Invalid preimage");
        require(swaps[_swapId].timelock > block.timestamp, "Timelock expired");
        require(!swaps[_swapId].withdrawn, "Already withdrawn");
        require(!swaps[_swapId].refunded, "Already refunded");
        _;
    }
    
    modifier refundable(bytes32 _swapId) {
        require(swaps[_swapId].timelock <= block.timestamp, "Timelock not expired");
        require(!swaps[_swapId].withdrawn, "Already withdrawn");
        require(!swaps[_swapId].refunded, "Already refunded");
        _;
    }

    /**
     * @dev Initiate a cross-chain swap
     * @param _participant Address that can withdraw the funds
     * @param _hashlock Hash of the secret
     * @param _timelock Unix timestamp when refund becomes available
     * @param _polkadotAddress Destination address on Polkadot
     */
    function initiateSwap(
        address _participant,
        bytes32 _hashlock,
        uint256 _timelock,
        string memory _polkadotAddress
    ) external payable nonReentrant returns (bytes32 swapId) {
        require(msg.value > 0, "Amount must be greater than 0");
        require(_participant != address(0), "Invalid participant address");
        require(_timelock > block.timestamp + MIN_TIMELOCK, "Timelock too short");
        require(bytes(_polkadotAddress).length > 0, "Invalid Polkadot address");
        
        swapId = keccak256(abi.encodePacked(
            msg.sender,
            _participant,
            msg.value,
            _hashlock,
            _timelock,
            block.timestamp
        ));
        
        require(swaps[swapId].initiator == address(0), "Swap already exists");
        
        swaps[swapId] = Swap({
            initiator: msg.sender,
            participant: _participant,
            amount: msg.value,
            hashlock: _hashlock,
            timelock: _timelock,
            withdrawn: false,
            refunded: false,
            polkadotAddress: _polkadotAddress
        });
        
        emit SwapInitiated(
            swapId,
            msg.sender,
            _participant,
            msg.value,
            _hashlock,
            _timelock,
            _polkadotAddress
        );
    }

    /**
     * @dev Withdraw funds by revealing the preimage
     * @param _swapId The swap identifier
     * @param _preimage The secret that hashes to the hashlock
     */
    function withdraw(bytes32 _swapId, bytes32 _preimage)
        external
        nonReentrant
        swapExists(_swapId)
        withdrawable(_swapId, _preimage)
    {
        Swap storage swap = swaps[_swapId];
        require(msg.sender == swap.participant, "Only participant can withdraw");
        
        swap.withdrawn = true;
        
        (bool success, ) = payable(swap.participant).call{value: swap.amount}("");
        require(success, "Transfer failed");
        
        emit SwapWithdrawn(_swapId, _preimage);
    }

    /**
     * @dev Refund the swap after timelock expires
     * @param _swapId The swap identifier
     */
    function refund(bytes32 _swapId)
        external
        nonReentrant
        swapExists(_swapId)
        refundable(_swapId)
    {
        Swap storage swap = swaps[_swapId];
        require(msg.sender == swap.initiator, "Only initiator can refund");
        
        swap.refunded = true;
        
        (bool success, ) = payable(swap.initiator).call{value: swap.amount}("");
        require(success, "Refund failed");
        
        emit SwapRefunded(_swapId);
    }

    /**
     * @dev Get swap details
     * @param _swapId The swap identifier
     */
    function getSwap(bytes32 _swapId) external view returns (
        address initiator,
        address participant,
        uint256 amount,
        bytes32 hashlock,
        uint256 timelock,
        bool withdrawn,
        bool refunded,
        string memory polkadotAddress
    ) {
        Swap storage swap = swaps[_swapId];
        return (
            swap.initiator,
            swap.participant,
            swap.amount,
            swap.hashlock,
            swap.timelock,
            swap.withdrawn,
            swap.refunded,
            swap.polkadotAddress
        );
    }

    /**
     * @dev Check if swap is active (not withdrawn or refunded)
     * @param _swapId The swap identifier
     */
    function isSwapActive(bytes32 _swapId) external view returns (bool) {
        Swap storage swap = swaps[_swapId];
        return swap.initiator != address(0) && !swap.withdrawn && !swap.refunded;
    }
}