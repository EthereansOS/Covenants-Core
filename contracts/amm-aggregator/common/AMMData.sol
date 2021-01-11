//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

struct LiquidityPoolData {
    address liquidityPoolAddress;
    uint256 liquidityPoolAmount;
    address[] tokens;
    uint256[] amounts;
    address receiver;
}

struct LiquidityToSwap {
    bool enterInETH;
    bool exitInETH;
    address[] liquidityPoolAddresses;
    address[] paths;
    address inputToken;
    uint256 amount;
    address receiver;
}