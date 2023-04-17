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

    function setEntry(RoutinesEntry memory entryData, RoutinesOperation[] memory operations) external;

    function flushBack(address[] memory tokenAddresses) external;
}