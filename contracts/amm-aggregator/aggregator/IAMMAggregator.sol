//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "../common/IAMM.sol";

interface IAMMAggregator is IAMM {

    function host() external view returns (address);

    function setHost(address newHost) external;

    function amms() external view returns (address[] memory);

    function remove(uint256) external;

    function add(address[] calldata) external;

    function findByLiquidityPool(address liquidityPoolAddress) external view returns(uint256, uint256[] memory, address[] memory, address);

    function info(address liquidityPoolAddress) external view returns(string memory name, uint256 version, address amm);

    function data(address liquidityPoolAddress) external view returns(address ethereumAddress, uint256 maxTokensPerLiquidityPool, bool hasUniqueLiquidityPools, address amm);

    event AMM(address indexed amm, string name, uint256 version);
}

interface IDoubleProxy {
    function proxy() external view returns (address);
}

interface IMVDProxy {
    function getMVDFunctionalitiesManagerAddress() external view returns(address);
    function getMVDWalletAddress() external view returns (address);
    function getStateHolderAddress() external view returns(address);
}

interface IMVDFunctionalitiesManager {
    function isAuthorizedFunctionality(address functionality) external view returns(bool);
}

interface IStateHolder {
    function getBool(string calldata varName) external view returns (bool);
    function getUint256(string calldata name) external view returns(uint256);
    function getAddress(string calldata name) external view returns(address);
    function clear(string calldata varName) external returns(string memory oldDataType, bytes memory oldVal);
}