//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

struct PrestoOperation {

    address inputTokenAddress;
    uint256 inputTokenAmount;

    address ammPlugin;
    address[] liquidityPoolAddresses;
    address[] swapPath;
    bool enterInETH;
    bool exitInETH;

    uint256[] tokenMins;

    address[] receivers;
    uint256[] receiversPercentages;
}