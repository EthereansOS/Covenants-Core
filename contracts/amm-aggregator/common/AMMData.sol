//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

struct LiquidityPoolData {
    address liquidityPoolAddress; // setup
    uint256 amount; // posizione
    address tokenAddress; // setup
    bool amountIsLiquidityPool; // true
    bool involvingETH; // setup
    address receiver; // msg.sender (free == uniqueOwner)
}

struct SwapData {
    bool enterInETH;
    bool exitInETH;
    address[] liquidityPoolAddresses;
    address[] paths;
    address inputToken;
    uint256 amount;
    address receiver;
}