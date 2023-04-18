//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct RoutinesEntry {
    string name;
    uint256 eventInterval;
    uint256 lastEvent;
    uint256 callerRewardPercentage;
}

struct RoutinesOperation {
    address inputTokenAddress;
    uint256 inputTokenAmount;
    bool inputTokenAmountIsPercentage;
    bool inputTokenAmountIsByMint;

    address ammPlugin;
    address[] liquidityPoolAddresses;
    address[] swapPath;
    bool enterInETH;
    bool exitInETH;

    address[] receivers;
    uint256[] receiversPercentages;
}

interface IRoutines {
    function entry() external view returns(RoutinesEntry memory, RoutinesOperation[] memory);

    function setEntry(RoutinesEntry calldata entryData, RoutinesOperation[] memory operations) external;

    function nextEvent() external view returns(uint256);

    function execute(bool earnByAmounts, address rewardReceiver, uint256[] calldata minAmounts) external returns(bool executed, uint256[] memory outputAmounts);

    function flushBack(address[] calldata tokenAddresses) external;
}