//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface IFixedInflationFactory {

    event ExtensionCloned(address indexed);

    function fixedInflationDefaultExtension() external view returns (address);

    function feePercentageInfo() external view returns (uint256, address);

    function cloneLiquidityMiningDefaultExtension() external returns(address clonedExtension);
}