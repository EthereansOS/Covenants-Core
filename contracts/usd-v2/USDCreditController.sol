//SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "./util/ERC1155Receiver.sol";
import "./util/INativeV1.sol";

contract USDCreditController is ERC1155Receiver {

    address private _usdCollection;
    uint256 private _usdObjectId;
    uint256 private _usdCreditObjectId;

    function init(address usdCollection, uint256 usdObjectId, uint256 usdCreditObjectId) public {
        require(_usdCollection == address(0), "Init already called!");
        _usdCollection = usdCollection;
        _usdObjectId = usdObjectId;
        _usdCreditObjectId = usdCreditObjectId;
    }

    function onERC1155BatchReceived(
        address,
        address from,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    )
        public
        override
        returns(bytes4) {
            require(msg.sender == _usdCollection, "Only uSD collection allowed here");
            uint256[] memory usdIds = new uint256[](ids.length);
            for(uint256 i = 0; i < ids.length; i++) {
                require(ids[i] == _usdCreditObjectId, "Only usd Credit allowed here");
                usdIds[i] = _usdObjectId;
            }
            INativeV1 collection = INativeV1(_usdCollection);
            collection.burnBatch(ids, values);
            collection.safeBatchTransferFrom(address(this), from, usdIds, values, data);
            return this.onERC1155BatchReceived.selector;
    }

    function onERC1155Received(
        address,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    )
        public
        override
        returns(bytes4) {
            require(msg.sender == _usdCollection, "Only uSD collection allowed here");
            require(id == _usdCreditObjectId, "Only usd Credit allowed here");
            INativeV1 collection = INativeV1(_usdCollection);
            collection.burn(id, value);
            collection.safeTransferFrom(address(this), from, _usdObjectId, value, data);
            return this.onERC1155Received.selector;
    }
}