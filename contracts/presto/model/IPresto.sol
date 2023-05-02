//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct PrestoOperation {

    uint256 liquidityPoolIdOrInputTokenAddress;
    uint256 amount;

    address ammPlugin;
    uint256[] liquidityPoolIds;
    address[] swapPath;
    bool enterInETH;
    bool exitInETH;

    bytes additionalData;

    uint256[] tokenMins;

    address[] receivers;
    uint256[] receiversPercentages;

    uint256 deadline;
}

interface IPresto {
    function execute(PrestoOperation[] memory operations) external payable returns(uint256[] memory outputAmounts);
}