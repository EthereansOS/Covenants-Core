//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./FixedInflationData.sol";
import "./IFixedInflationExtension.sol";
import "./util/DFOHub.sol";

contract FixedInflationExtension is IFixedInflationExtension {

    string private constant FUNCTIONALITY_NAME = "manageFixedInflation";

    address private _doubleProxy;

    address private _fixedInflationContract;

    modifier onlyFixedInflationContract() {
        require(_fixedInflationContract == msg.sender, "Unauthorized");
        _;
    }

    modifier onlyDFO() {
        require(_isFromDFO(msg.sender), "Unauthorized");
        _;
    }

    function init(address doubleProxyAddress) override public {
        require(_doubleProxy == address(0), "Already init");
        _doubleProxy = doubleProxyAddress;
        _fixedInflationContract = msg.sender;
    }

    function setDoubleProxy(address newDoubleProxy) public onlyDFO {
        _doubleProxy = newDoubleProxy;
    }

    function receiveTokens(address[] memory tokenAddresses, uint256[] memory transferAmounts, uint256[] memory amountsToMint) public override onlyFixedInflationContract {
        IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).submit(FUNCTIONALITY_NAME, abi.encode(address(0), 0, tokenAddresses, transferAmounts, amountsToMint, _fixedInflationContract));
    }

    function _getFunctionalityAddress() private view returns(address functionalityAddress) {
        (functionalityAddress,,,,) = IMVDFunctionalitiesManager(IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDFunctionalitiesManagerAddress()).getFunctionalityData(FUNCTIONALITY_NAME);
    }

    function _getDFOWallet() private view returns(address) {
        return IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDWalletAddress();
    }

    function _isFromDFO(address sender) private view returns(bool) {
        return IMVDFunctionalitiesManager(IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDFunctionalitiesManagerAddress()).isAuthorizedFunctionality(sender);
    }
}