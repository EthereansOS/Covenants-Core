//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IAMM.sol";

interface IAMMAggregator is IAMM {

    function host() external view returns (address);

    function setHost(address newHost) external;

    function amms() external view returns (address[] memory);

    function isAMM(address pluginAddress) external view returns(bool);

    function add(address[] memory ammsToAdd) external;

    function findByLiquidityPool(uint256 liquidityPoolId) external view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory tokensAddresses, address amm);

    function info(uint256 liquidityPoolId) external view returns(string memory name, uint256 version, address amm);

    function data(uint256 liquidityPoolId) external view returns(address ethereumAddress, uint256 maxTokensPerLiquidityPool, bool hasUniqueLiquidityPools, address amm);

    event AMM(address indexed amm, string name, uint256 version);
}