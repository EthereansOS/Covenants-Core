//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

struct FixedInflationEntry {
    uint256 lastBlock;
    uint256 blockInterval;

    FixedInflationOperationSet[] operationSets;
}

struct FixedInflationOperationSet {
    address ammPlugin;
    FixedInflationOperation[] operations;
}

struct TokenData {
    address tokenAddress;
    uint256 amount;
    bool amountIsPercentage;
    bool amountByMint;
}

struct FixedInflationOperation {

    TokenData inputToken;

    address liquidityPoolAddress;
    address[] swapPath;

    address receiver;

    uint256 byEarnPercentage;

    TokenData rewardToken;
}