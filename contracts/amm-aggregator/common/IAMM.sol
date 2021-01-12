//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./AMMData.sol";

interface IAMM {

    function info() external pure returns(string memory name, uint256 version);

    function ethereumAddress() external view returns(address);

    function addLiquidity(LiquidityPoolData calldata data) external payable returns(uint256, uint256[] memory);
    function addLiquidityBatch(LiquidityPoolData[] calldata data) external payable returns(uint256[] memory, uint256[][] memory);

    function removeLiquidity(LiquidityPoolData calldata data) external returns(uint256[] memory);
    function removeLiquidityBatch(LiquidityPoolData[] calldata data) external returns(uint256[][] memory);

    function swapLiquidity(LiquidityToSwap calldata data) external payable returns(uint256);

    function tokens(address liquidityPoolAddress) external view returns(address[] memory);
    function liquidityPool(address[] memory liquidityPoolTokens) external view returns(address);

    function amounts(address liquidityPoolAddress) external view returns(uint256, uint256[] memory);

    function inPercentage(address liquidityPoolAddress, uint256 numerator, uint256 denominator, uint256 normalizeTokenAmountsToTheseDecimals) external view returns (uint256, uint256[] memory);
    function inPercentage(address liquidityPoolAddress, uint256 numerator, uint256 denominator) external view returns (uint256, uint256[] memory);

    function byLiquidityPoolAmount(address liquidityPoolAddress, uint256 liquidityPoolAmount, uint256 normalizeTokenAmountsToTheseDecimals) external view returns(uint256[] memory);
    function byLiquidityPoolAmount(address liquidityPoolAddress, uint256 liquidityPoolAmount) external view returns(uint256[] memory);

    function byTokenAmount(address liquidityPoolAddress, address tokenAddress, uint256 tokenAmount, uint256 normalizeTokenAmountsToTheseDecimals) external view returns(uint256, uint256[] memory);
    function byTokenAmount(address liquidityPoolAddress, address tokenAddress, uint256 tokenAmount) external view returns(uint256, uint256[] memory);
}