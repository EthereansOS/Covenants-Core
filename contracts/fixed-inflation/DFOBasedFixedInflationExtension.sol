//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./FixedInflationData.sol";
import "./IFixedInflationExtension.sol";
import "./util/DFOHub.sol";

contract DFOBasedFixedInflationExtension is IFixedInflationExtension {

    string private constant FUNCTIONALITY_NAME = "manageFixedInflation";

    address private _host;

    address private _fixedInflationContract;

    modifier fixedInflationOnly() {
        require(_fixedInflationContract == msg.sender, "Unauthorized");
        _;
    }

    modifier hostOnly() {
        require(_isFromDFO(msg.sender), "Unauthorized");
        _;
    }

    function init(address doubleProxyAddress) override public {
        require(_host == address(0), "Already init");
        _host = doubleProxyAddress;
        _fixedInflationContract = msg.sender;
    }

    function data() view public override returns(address fixedInflationContract, address host) {
        return(_fixedInflationContract, _host);
    }

    function setHost(address host) public virtual override hostOnly {
        _host = host;
    }

    function receiveTokens(address[] memory tokenAddresses, uint256[] memory transferAmounts, uint256[] memory amountsToMint) public override fixedInflationOnly {
        IMVDProxy(IDoubleProxy(_host).proxy()).submit(FUNCTIONALITY_NAME, abi.encode(address(0), 0, tokenAddresses, transferAmounts, amountsToMint, _fixedInflationContract));
    }

    function _getFunctionalityAddress() private view returns(address functionalityAddress) {
        (functionalityAddress,,,,) = IMVDFunctionalitiesManager(IMVDProxy(IDoubleProxy(_host).proxy()).getMVDFunctionalitiesManagerAddress()).getFunctionalityData(FUNCTIONALITY_NAME);
    }

    function _getDFOWallet() private view returns(address) {
        return IMVDProxy(IDoubleProxy(_host).proxy()).getMVDWalletAddress();
    }

    function _isFromDFO(address sender) private view returns(bool) {
        return IMVDFunctionalitiesManager(IMVDProxy(IDoubleProxy(_host).proxy()).getMVDFunctionalitiesManagerAddress()).isAuthorizedFunctionality(sender);
    }
}