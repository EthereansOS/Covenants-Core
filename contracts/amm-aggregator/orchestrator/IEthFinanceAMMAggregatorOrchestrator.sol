//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IEthFinanceAMMAggregatorOrchestrator {

    /**
     * @dev GET - The DoubleProxy of the DFO linked to this Contract
     */
    function doubleProxy() external view returns (address);

    /**
     * @dev SET - The DoubleProxy of the DFO linked to this Contract
     * It can be done only through a Proposal in the Linked DFO
     * @param newDoubleProxy the new DoubleProxy address
     */
    function setDoubleProxy(address newDoubleProxy) external;
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