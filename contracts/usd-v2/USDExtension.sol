//SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "./util/IEthItemOrchestrator.sol";
import "./util/INativeV1.sol";
import "./util/IERC20.sol";

contract USDExtension {

    address private _controller;

    address private _collection;
    uint256 private _objectId;
    address private _interoperableInterfaceAddress;

    constructor(address orchestrator, string memory name, string memory symbol, string memory collectionUri, string memory itemUri) {
        _controller = msg.sender;
        (_collection,) = IEthItemOrchestrator(orchestrator).createNative(abi.encode("init(string,string,bool,string,address,bytes)", name, symbol, true, collectionUri, address(this), ""), "");
        INativeV1 coll = INativeV1(_collection);
        (_objectId, _interoperableInterfaceAddress) = coll.mint(10**18, "", "", itemUri, true);
        coll.burn(_objectId, coll.balanceOf(address(this), _objectId));
    }

    function collection() public view returns (address) {
        return _collection;
    }

    function objectId() public view returns (uint256) {
        return _objectId;
    }

    function interoperableInterface() public view returns (address) {
        return _interoperableInterfaceAddress;
    }

    function info() public view returns (address, uint256, address) {
        return (_collection, _objectId, _interoperableInterfaceAddress);
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

    function mint(uint256 amount, address receiver) public controllerOnly {
        INativeV1(_collection).mint(_objectId, amount);
        IERC20(_interoperableInterfaceAddress).transfer(receiver, IERC20(_interoperableInterfaceAddress).balanceOf(address(this)));
    }

    function setCollectionUri(string memory uri) public controllerOnly {
        INativeV1(_collection).setUri(uri);
    }

    function setItemUri(string memory uri) public controllerOnly {
        INativeV1(_collection).setUri(_objectId, uri);
    }
}