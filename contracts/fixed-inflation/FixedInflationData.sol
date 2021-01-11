//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

struct FixedInflationEntryConfiguration {
    bool add;
    bool remove;
    uint256 index;
    uint256 blockInterval;
    address[] ammPlugins;
}

struct FixedInflationEntry {
    uint256 lastBlock;
    uint256 blockInterval;
    address[] ammPlugins;
}

struct FixedInflationOperation {

    TokenData inputToken;

    address[] liquidityPoolAddresses;
    address[] swapPath;

    address receiver;

    uint256 byEarnPercentage;

    TokenData rewardToken;
}

struct TokenData {
    address tokenAddress;
    uint256 amount;
    bool amountIsPercentage;
    bool amountByMint;
}