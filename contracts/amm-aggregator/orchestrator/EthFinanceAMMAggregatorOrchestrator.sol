//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./IEthFinanceAMMAggregatorOrchestrator.sol";
import "../util/ERC165.sol";

contract EthFinanceAMMAggregatorOrchestrator is IEthFinanceAMMAggregatorOrchestrator, ERC165 {

    address private _doubleProxy;

    constructor(address dFODoubleProxy) {
        _doubleProxy = dFODoubleProxy;
    }

    modifier byDFO virtual {
        require(_isFromDFO(msg.sender), "Unauthorized Action!");
        _;
    }

    function _isFromDFO(address sender) private view returns(bool) {
        IMVDProxy proxy = IMVDProxy(IDoubleProxy(_doubleProxy).proxy());
        if(IMVDFunctionalitiesManager(proxy.getMVDFunctionalitiesManagerAddress()).isAuthorizedFunctionality(sender)) {
            return true;
        }
        return proxy.getMVDWalletAddress() == sender;
    }

    function doubleProxy() public view override returns (address) {
        return _doubleProxy;
    }

    function setDoubleProxy(address newDoubleProxy) public override byDFO {
        _doubleProxy = newDoubleProxy;
    }
}