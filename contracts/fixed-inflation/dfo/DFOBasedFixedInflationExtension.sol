//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "../FixedInflationData.sol";
import "../IFixedInflationExtension.sol";
import "../util/DFOHub.sol";
import "../IFixedInflation.sol";
import "../util/IERC20.sol";
import "../util/IERC20Burnable.sol";

contract DFOBasedFixedInflationExtension is IFixedInflationExtension {

    string private constant FUNCTIONALITY_NAME = "manageFixedInflation";

    address private _host;

    address private _fixedInflationContract;

    bool public override active;

    modifier fixedInflationOnly() {
        require(_fixedInflationContract == msg.sender, "Unauthorized");
        _;
    }

    receive() external payable {
    }

    modifier hostOnly() {
        require(_isFromDFO(msg.sender), "Unauthorized");
        _;
    }

    function init(address doubleProxyAddress) override public {
        require(_host == address(0), "Already init");
        require((_host = doubleProxyAddress) != address(0), "blank host");
        _fixedInflationContract = msg.sender;
    }

    function data() view public override returns(address fixedInflationContract, address host) {
        return(_fixedInflationContract, _host);
    }

    function setHost(address host) public virtual override hostOnly {
        _host = host;
    }

    function setActive(bool _active) public override virtual hostOnly {
        active = _active;
    }

    function receiveTokens(address[] memory tokenAddresses, uint256[] memory transferAmounts, uint256[] memory amountsToMint) public override fixedInflationOnly {
        IMVDProxy(IDoubleProxy(_host).proxy()).submit(FUNCTIONALITY_NAME, abi.encode(address(0), 0, tokenAddresses, transferAmounts, amountsToMint, _fixedInflationContract));
    }

    function setEntry(FixedInflationEntry memory newEntry, FixedInflationOperation[] memory newOperations) public override hostOnly {
        IFixedInflation(_fixedInflationContract).setEntry(newEntry, newOperations);
    }

    function flushBack(address[] memory tokenAddresses) public override hostOnly {
        IFixedInflation(_fixedInflationContract).flushBack(tokenAddresses);
        address walletAddress = _getDFOWallet();
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            _transferTo(tokenAddresses[i], walletAddress, _balanceOf(tokenAddresses[i]));
        }
    }

    function deactivationByFailure() public override fixedInflationOnly {
        active = false;
    }

    function burnToken(address erc20TokenAddress, uint256 value) external override fixedInflationOnly {
        _safeTransferFrom(erc20TokenAddress, _fixedInflationContract, address(this), value);
        _burn(erc20TokenAddress, value);
    }

    function _burn(address erc20TokenAddress, uint256 value) internal virtual {
        IERC20Burnable(erc20TokenAddress).burn(value);
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

    function _balanceOf(address tokenAddress) private view returns (uint256) {
        if(tokenAddress == address(0)) {
            return address(this).balance;
        }
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function _transferTo(address erc20TokenAddress, address to, uint256 value) private {
        if(value == 0) {
            return;
        }
        if(erc20TokenAddress == address(0)) {
            (bool result,) = to.call{value:value}("");
            require(result, "ETH transfer failed");
            return;
        }
        _safeTransfer(erc20TokenAddress, to, value);
    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) private {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFER_FAILED');
    }

    function _safeTransferFrom(address erc20TokenAddress, address from, address to, uint256 value) internal {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).transferFrom.selector, from, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFERFROM_FAILED');
    }

    function _call(address location, bytes memory payload) private returns(bytes memory returnData) {
        assembly {
            let result := call(gas(), location, 0, add(payload, 0x20), mload(payload), 0, 0)
            let size := returndatasize()
            returnData := mload(0x40)
            mstore(returnData, size)
            let returnDataPayloadStart := add(returnData, 0x20)
            returndatacopy(returnDataPayloadStart, 0, size)
            mstore(0x40, add(returnDataPayloadStart, size))
            switch result case 0 {revert(returnDataPayloadStart, size)}
        }
    }
}