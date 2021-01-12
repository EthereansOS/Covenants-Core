//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

struct FixedInflationEntryConfiguration {
    bool add;
    bool remove;
    uint256 index;
    uint256 blockInterval;
    uint256 callerRewardPercentage;
}

struct FixedInflationEntry {
    uint256 lastBlock;
    uint256 blockInterval;
    uint256 callerRewardPercentage;
}

struct FixedInflationOperation {

    TokenData inputToken;

    address ammPlugin;
    address[] liquidityPoolAddresses;
    address[] swapPath;

    uint256[] receiversPercentages;
    address[] receivers;
}

struct TokenData {
    address tokenAddress;
    uint256 amount;
    bool amountIsPercentage;
    bool amountByMint;
}