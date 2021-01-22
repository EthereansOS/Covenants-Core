//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "./util/IEthItemOrchestrator.sol";
import "./util/INativeV1.sol";
import "./util/IERC20.sol";

contract WUSDExtension {

    uint256 private constant DECIMALS = 18;

    address private _controller;

    address private _collection;

    constructor(address orchestrator, string memory name, string memory symbol, string memory collectionUri) {
        _controller = msg.sender;
        (_collection,) = IEthItemOrchestrator(orchestrator).createNative(abi.encodeWithSignature("init(string,string,bool,string,address,bytes)", name, symbol, true, collectionUri, address(this), ""), "");
    }

    function collection() public view returns (address) {
        return _collection;
    }

    function controller() public view returns (address) {
        return _controller;
    }

    modifier controllerOnly() {
        require(msg.sender == _controller, "Unauthorized action");
        _;
    }

    function setController(address newController) public controllerOnly {
        _controller = newController;
    }

    function mint(uint256 objectId, uint256 amount, address receiver) public controllerOnly {
        INativeV1(_collection).mint(objectId, amount);
        INativeV1(_collection).safeTransferFrom(address(this), receiver, objectId, INativeV1(_collection).balanceOf(address(this), objectId), "");
    }

    function mint(uint256 amount, string calldata tokenName, string calldata tokenSymbol, string calldata objectUri, bool editable, address receiver) public controllerOnly returns(uint256 objectId, address interoperableInterfaceAddress) {
        (objectId, interoperableInterfaceAddress) = INativeV1(_collection).mint(amount, tokenName, tokenSymbol, objectUri, editable);
        INativeV1(_collection).safeTransferFrom(address(this), receiver, objectId, INativeV1(_collection).balanceOf(address(this), objectId), "");
    }

    function mintEmpty(string calldata tokenName, string calldata tokenSymbol, string calldata objectUri, bool editable) public controllerOnly returns(uint256 objectId, address interoperableInterfaceAddress) {
        INativeV1 theCollection = INativeV1(_collection);
        (objectId, interoperableInterfaceAddress) = theCollection.mint(10**18, tokenName, tokenSymbol, objectUri, editable);
        theCollection.burn(objectId, theCollection.balanceOf(address(this), objectId));
    }

    function setCollectionUri(string memory uri) public controllerOnly {
        INativeV1(_collection).setUri(uri);
    }

    function setItemUri(uint256 existingObjectId, string memory uri) public controllerOnly {
        INativeV1(_collection).setUri(existingObjectId, uri);
    }

    function makeReadOnly(uint256 objectId) public controllerOnly {
        INativeV1(_collection).makeReadOnly(objectId);
    }

    function send(address[] memory tokenAddresses, uint256[] memory amounts, address[] memory receivers) public controllerOnly {
        require(tokenAddresses.length > 0 && tokenAddresses.length == amounts.length, "tokenAddresses and amounts must have same length");
        require(receivers.length == 1 || receivers.length == amounts.length, "Specify just a receiver or a length equals to tokensAddresses");
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            address receiver = receivers.length == 1 ? receivers[0] : receivers[i];
            if(tokenAddresses[i] == address(0)) {
                payable(receiver).transfer(amounts[i]);
            } else {
                _safeTransfer(tokenAddresses[i], receiver, amounts[i]);
            }
        }
    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) internal {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFER_FAILED');
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