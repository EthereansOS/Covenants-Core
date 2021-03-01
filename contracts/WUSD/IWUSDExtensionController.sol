//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma abicoder v2;

import "./AllowedAMM.sol";

interface IWUSDExtensionController {

    function rebalanceByCreditBlockInterval() external view returns(uint256);

    function lastRebalanceByCreditBlock() external view returns(uint256);

    function wusdInfo() external view returns (address, uint256, address);

    function allowedAMMs() external view returns(AllowedAMM[] memory);

    function extension() external view returns (address);

    function addLiquidity(
        uint256 ammPosition,
        uint256 liquidityPoolPosition,
        uint256 liquidityPoolAmount,
        bool byLiquidityPool
    ) external returns(uint256);
}