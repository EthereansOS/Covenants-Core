//SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "./util/IEthItemOrchestrator.sol";
import "./util/INativeV1.sol";
import "./util/IERC20.sol";

contract USDExtension {

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

    function setCollectionUri(string memory uri) public controllerOnly {
        INativeV1(_collection).setUri(uri);
    }

    function setItemUri(uint256 existingObjectId, string memory uri) public controllerOnly {
        INativeV1(_collection).setUri(existingObjectId, uri);
    }

    function makeReadOnly(uint256 objectId) public controllerOnly {
        INativeV1(_collection).makeReadOnly(objectId);
    }
}