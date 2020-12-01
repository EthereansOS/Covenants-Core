//SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "./USDExtension.sol";
import "./util/DFOHub.sol";
import "./util/ERC1155Receiver.sol";

contract USDExtensionController is ERC1155Receiver {

    address private _doubleProxy;

    address private _extension;

    address private _collection;

    constructor(address doubleProxyAddress, address orchestratorAddress, 
        string memory name, string memory symbol, string memory collectionUri, string memory itemUri) {
        _doubleProxy = doubleProxyAddress;
        _extension = address(new USDExtension(orchestratorAddress, name, symbol, collectionUri, itemUri));
    }

    function doubleProxy() public view returns (address) {
        return _doubleProxy;
    }

    function extension() public view returns (address) {
        return _extension;
    }

    modifier byDFO virtual {
        require(_isFromDFO(msg.sender), "Unauthorized Action!");
        _;
    }

    function _isFromDFO(address sender) private view returns(bool) {
        return IMVDFunctionalitiesManager(IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDFunctionalitiesManagerAddress()).isAuthorizedFunctionality(sender);
    }

    function setDoubleProxy(address newDoubleProxy) public byDFO {
        _doubleProxy = newDoubleProxy;
    }

    function changeController(address controller) public byDFO {
        USDExtension(_extension).setController(controller);
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    )
        public override
        returns(bytes4) {
            return this.onERC1155Received.selector;
        }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    )
        public override
        returns(bytes4) {
            return this.onERC1155BatchReceived.selector;
        }
}