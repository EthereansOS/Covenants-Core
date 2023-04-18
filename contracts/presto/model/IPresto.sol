//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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

interface IPresto {
    function execute(PrestoOperation[] memory operations) external payable returns(uint256[] memory outputAmounts);
}