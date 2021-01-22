//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

struct FixedInflationEntryConfiguration {
    bool add;
    bool remove;
    FixedInflationEntry data;
}

struct FixedInflationEntry {
    uint256 lastBlock;
    bytes32 id;
    string name;
    uint256 blockInterval;
    uint256 callerRewardPercentage;
}

struct FixedInflationOperation {

    address inputTokenAddress;
    uint256 inputTokenAmount;
    bool inputTokenAmountIsPercentage;
    bool inputTokenAmountIsByMint;

    address ammPlugin;
    address[] liquidityPoolAddresses;
    address[] swapPath;

    address[] receivers;
    uint256[] receiversPercentages;
}