// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// Lottery
// Enter the lottery (with some amount)
// Pick the winner after some time (automated)
// Chainlink for randomness outside the blockchain, and event firing

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

error Lottery__NotEnoughEthEntered();
error Lottery__TransferFailed();
error Lottery__NotOpen();
error Lottery__UpkeepNotNeeded(uint256 currentBalance, uint256 numEntrants, uint256 lotteryState);

contract Lottery is VRFConsumerBaseV2, AutomationCompatibleInterface {
    // Type declarations
    enum lotteryState {
        OPEN,
        CALCULATING
    }

    // state variables
    uint256 private immutable i_entranceFee;
    address payable[] private s_entrants;
    VRFCoordinatorV2Interface private immutable i_COORDINATOR;
    bytes32 private immutable i_keyHash;
    uint64 private immutable i_subscriptionId;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant NUM_WORDS = 1;

    // Lottery variables
    address private s_recentWinner;
    lotteryState private s_lotteryState;
    uint256 private s_lastTimeStamp;
    uint256 private immutable i_interval;

    event LotteryEnter(address indexed entrant);
    event RequestedLottteryWinner(uint256 indexed requestId);
    event LotteryWinner(address indexed winner);

    constructor(
        uint256 entranceFee,
        bytes32 keyHash,
        uint64 subscriptionId,
        uint32 callbackGasLimit,
        uint256 interval
    ) VRFConsumerBaseV2(0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D) {
        i_entranceFee = entranceFee;
        i_COORDINATOR = VRFCoordinatorV2Interface(0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D);
        i_keyHash = keyHash;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_lotteryState = lotteryState.OPEN;
        s_lastTimeStamp = block.timestamp;
        i_interval = interval;
    }

    function enterLottery() public payable {
        if (msg.value < i_entranceFee) {
            revert Lottery__NotEnoughEthEntered();
        }
        if (s_lotteryState != lotteryState.OPEN) {
            revert Lottery__NotOpen();
        }
        s_entrants.push(payable(msg.sender));
        emit LotteryEnter(msg.sender);
    }

    function checkUpkeep(
        bytes memory /* checkData */
    ) public override returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool isOpen = (s_lotteryState == lotteryState.OPEN);
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasEntrants = (s_entrants.length > 0);
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (isOpen && timePassed && hasEntrants && hasBalance);
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Lottery__UpkeepNotNeeded(
                address(this).balance,
                s_entrants.length,
                uint256(s_lotteryState)
            );
        }
        s_lotteryState = lotteryState.CALCULATING;
        uint256 requestId = i_COORDINATOR.requestRandomWords(
            i_keyHash,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );

        emit RequestedLottteryWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_entrants.length;
        address payable winnerAddr = s_entrants[indexOfWinner];
        s_recentWinner = winnerAddr;
        s_lotteryState = lotteryState.OPEN;
        s_entrants = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        (bool success, ) = winnerAddr.call{value: address(this).balance}("");

        if (!success) {
            revert Lottery__TransferFailed();
        }

        emit LotteryWinner(winnerAddr);
    }

    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getEntrants(uint256 index) public view returns (address) {
        return s_entrants[index];
    }

    function getRecentWiner() public view returns (address) {
        return s_recentWinner;
    }
}
