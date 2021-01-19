//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "./util/ERC1155Receiver.sol";
import "./util/INativeV1.sol";
import "./IWUSDNoteController.sol";

contract WUSDNoteController is IWUSDNoteController, ERC1155Receiver {

    address public override wusdCollection;
    uint256 public override wusdObjectId;
    uint256 public override wusdNoteObjectId;
    uint256 public override multiplier;

    function init(address _wusdCollection, uint256 _wusdObjectId, uint256 _wusdNoteObjectId, uint256 _multiplier) public override {
        require(wusdCollection == address(0), "Already init");
        wusdCollection = _wusdCollection;
        wusdObjectId = _wusdObjectId;
        wusdNoteObjectId = _wusdNoteObjectId;
        multiplier = _multiplier;
    }

    function info() public override view returns(address, uint256, uint256, uint256) {
        return (wusdCollection, wusdObjectId, wusdNoteObjectId, multiplier);
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
            require(msg.sender == wusdCollection, "Only WUSD collection allowed here");
            uint256[] memory usdIds = new uint256[](ids.length);
            uint256[] memory usdValues = new uint256[](ids.length);
            for(uint256 i = 0; i < ids.length; i++) {
                require(ids[i] == wusdNoteObjectId, "Only WUSD Note allowed here");
                usdIds[i] = wusdObjectId;
                usdValues[i] = values[i] * multiplier;
            }
            INativeV1 collection = INativeV1(wusdCollection);
            collection.burnBatch(ids, values);
            collection.safeBatchTransferFrom(address(this), from, usdIds, usdValues, data);
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
            require(msg.sender == wusdCollection, "Only WUSD collection allowed here");
            require(id == wusdNoteObjectId, "Only WUSD Note allowed here");
            INativeV1 collection = INativeV1(wusdCollection);
            collection.burn(id, value);
            collection.safeTransferFrom(address(this), from, wusdObjectId, value * multiplier, data);
            return this.onERC1155Received.selector;
    }
}