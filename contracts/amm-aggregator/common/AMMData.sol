//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

struct LiquidityProviderData {
    address liquidityProviderAddress;
    uint256 liquidityProviderAmount;
    address[] tokens;
    uint256[] amounts;
    address receiver;
}

struct LiquidityToSwap {
    address liquidityProviderAddress;
    uint256 liquidityProviderAmount;
    bool enterInETH;
    bool exitInETH;
    address[] tokens;
    uint256 amount;
    address receiver;
}