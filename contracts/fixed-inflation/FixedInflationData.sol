//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

struct FixedInflationEntry {
    string name;
    uint256 eventInterval;
    uint256 lastEvent;
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
    bool enterInETH;
    bool exitInETH;

    address[] receivers;
    uint256[] receiversPercentages;
}