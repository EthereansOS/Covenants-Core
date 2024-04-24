//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

interface IPeripheryPayments {

    function unwrapWETH9(uint256 amountMinimum, address recipient) external payable;

    function refundETH() external payable;

    function sweepToken(
        address token,
        uint256 amountMinimum,
        address recipient
    ) external payable;
}
