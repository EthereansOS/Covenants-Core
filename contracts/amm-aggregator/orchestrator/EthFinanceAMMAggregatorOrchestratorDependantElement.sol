//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "../util/ERC165.sol";
import "./IEthFinanceAMMAggregatorOrchestratorDependantElement.sol";
import "./IEthFinanceAMMAggregatorOrchestrator.sol";

abstract contract EthFinanceAMMAggregatorOrchestratorDependantElement is IEthFinanceAMMAggregatorOrchestratorDependantElement, ERC165 {

    string internal constant ETHFINANCE_AMM_ORCHESTRATOR_AUTHORIZED_KEY_PREFIX = "ehtfinance.amm.orchestrator.authorized";

    address internal _doubleProxy;

    constructor(address initialDoubleProxy) {
        _doubleProxy = initialDoubleProxy;
        _registerInterfaces();
        _registerSpecificInterfaces();
    }

    function _registerInterfaces() internal {
        _registerInterface(this.setDoubleProxy.selector);
    }

    function _registerSpecificInterfaces() internal virtual;

    modifier byOrchestrator virtual {
        require(isAuthorizedOrchestrator(msg.sender), "Unauthorized action");
        _;
    }

    function doubleProxy() public view override returns(address) {
        return _doubleProxy;
    }

    function setDoubleProxy(address newDoubleProxy) public override byOrchestrator {
        _doubleProxy = newDoubleProxy;
    }

    function isAuthorizedOrchestrator(address operator) public view override returns(bool) {
        return IStateHolder(IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getStateHolderAddress()).getBool(_toStateHolderKey(ETHFINANCE_AMM_ORCHESTRATOR_AUTHORIZED_KEY_PREFIX, _toString(operator)));
    }

    function _toStateHolderKey(string memory a, string memory b) internal pure returns(string memory) {
        return _toLowerCase(string(abi.encodePacked(a, ".", b)));
    }

    function _toString(address _addr) internal pure returns(string memory) {
        bytes32 value = bytes32(uint256(_addr));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint i = 0; i < 20; i++) {
            str[2+i*2] = alphabet[uint(uint8(value[i + 12] >> 4))];
            str[3+i*2] = alphabet[uint(uint8(value[i + 12] & 0x0f))];
        }
        return string(str);
    }

    function _toLowerCase(string memory str) internal pure returns(string memory) {
        bytes memory bStr = bytes(str);
        for (uint i = 0; i < bStr.length; i++) {
            bStr[i] = bStr[i] >= 0x41 && bStr[i] <= 0x5A ? bytes1(uint8(bStr[i]) + 0x20) : bStr[i];
        }
        return string(bStr);
    }
}