//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct PrestoOperation {

    address inputTokenAddress;
    uint256 inputTokenAmount;

    address ammPlugin;
    uint256[] liquidityPoolIds;
    address[] swapPath;
    bool involvingETHOrEnterInETH;
    bool amountIsLiquidityPoolOrExitInETH;

    bytes additionalData;

    uint256[] tokenMins;

    address[] receivers;
    uint256[] receiversPercentages;

    uint256 deadline;
}

interface IPresto {
    function execute(PrestoOperation[] memory operations) external payable returns(uint256[] memory outputAmounts);
}