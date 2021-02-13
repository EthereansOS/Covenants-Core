//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface ILiquidityMiningFactory {

    event ExtensionCloned(address indexed);

    function feePercentageInfo() external view returns (uint256, address);
    function liquidityMiningDefaultExtension() external view returns(address);
    function cloneLiquidityMiningDefaultExtension() external returns(address);
    function getLiquidityFarmTokenCollectionURI() external view returns (string memory);
    function getLiquidityFarmTokenURI() external view returns (string memory);

    function giveAndTransferCalculator() external view returns(address);
}