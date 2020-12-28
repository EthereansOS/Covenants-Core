//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./AMMData.sol";

interface IAMM {

    function info() external pure returns(string memory name, uint256 version);

    function addLiquidity(LiquidityPoolData calldata data) external payable returns(uint256);
    function addLiquidityBatch(LiquidityPoolData[] calldata data) external payable returns(uint256[] memory);

    function removeLiquidity(LiquidityPoolData calldata data) external returns(uint256[] memory);
    function removeLiquidityBatch(LiquidityPoolData[] calldata data) external returns(uint256[][] memory);

    function swapLiquidity(LiquidityToSwap calldata data) external payable;
    function swapLiquidityBatch(LiquidityToSwap[] calldata data) external payable;

    function tokens(address liquidityPoolAddress) external view returns(address[] memory);

    function inPercentage(address liquidityPoolAddress, uint256 numerator, uint256 denominator, uint256 normalizeToDecimals) external view returns (uint256, uint256[] memory);
    function inPercentage(address liquidityPoolAddress, uint256 numerator, uint256 denominator) external view returns (uint256, uint256[] memory);

    function byAmount(address liquidityPoolAddress, uint256 liquidityPoolAmount, uint256 normalizeToDecimals) external view returns(uint256[] memory);
    function byAmount(address liquidityPoolAddress, uint256 liquidityPoolAmount) external view returns(uint256[] memory);
}