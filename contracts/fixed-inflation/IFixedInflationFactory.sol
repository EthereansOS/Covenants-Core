//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface IFixedInflationFactory {

    function feePercentageInfo() external view returns (uint256, address);
}