//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

struct LiquidityPoolData {
    address liquidityPoolAddress;
    uint256 liquidityPoolAmount;
    address[] tokens;
    uint256[] amounts;
    address receiver;
}

struct LiquidityToSwap {
    address liquidityPoolAddress;
    uint256 liquidityPoolAmount;
    bool enterInETH;
    bool exitInETH;
    address[] tokens;
    uint256 amount;
    address receiver;
}