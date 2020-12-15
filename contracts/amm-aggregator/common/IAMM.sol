//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./AMMData.sol";

interface IAMM {

    function info() external pure returns(string memory name, uint256 version);

    function addLiquidity(LiquidityProviderData calldata data) external payable returns(uint256);
    function addLiquidityBatch(LiquidityProviderData[] calldata data) external payable returns(uint256[] memory);

    function removeLiquidity(LiquidityProviderData calldata data) external returns(uint256[] memory);
    function removeLiquidityBatch(LiquidityProviderData[] calldata data) external returns(uint256[][] memory);

    function swapLiquidity(LiquidityToSwap calldata data) external payable;
    function swapLiquidityBatch(LiquidityToSwap[] calldata data) external payable;

    function tokens(address liquidityProviderAddress) external view returns(address[] memory);

    function inPercentage(address liquidityProviderAddress, uint256 numerator, uint256 denominator, uint256 normalizeToDecimals) external view returns (uint256, uint256[] memory);
    function inPercentage(address liquidityProviderAddress, uint256 numerator, uint256 denominator) external view returns (uint256, uint256[] memory);

    function byAmount(address liquidityProviderAddress, uint256 liquidityProviderAmount, uint256 normalizeToDecimals) external view returns(uint256[] memory);
    function byAmount(address liquidityProviderAddress, uint256 liquidityProviderAmount) external view returns(uint256[] memory);
}