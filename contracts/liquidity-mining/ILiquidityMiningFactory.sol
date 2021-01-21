//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface ILiquidityMiningFactory {

    function feePercentageInfo() external view returns (uint256, address);

    function liquidityMiningDefaultExtension() external view returns(address);
}