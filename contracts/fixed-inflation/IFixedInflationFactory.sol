//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface IFixedInflationFactory {

    function fixedInflationDefaultExtension() external view returns (address);

    function feePercentageInfo() external view returns (uint256, address);
}