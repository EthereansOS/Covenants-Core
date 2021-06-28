//SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;
pragma abicoder v2;

import "./util/IEthItemOrchestrator.sol";
import "./util/INativeV1.sol";
import "./util/ERC1155Receiver.sol";
import "./IIndex.sol";
import "./util/DFOHub.sol";

contract Index is IIndex, ERC1155Receiver {

    address public override _doubleProxy;

    mapping(address => bool) _temporaryIndex;

    event NewIndex(uint256 indexed id, address indexed interoperableInterfaceAddress, address indexed token, uint256 amount);

    address public override collection;

    mapping(uint256 => address[]) public tokens;
    mapping(uint256 => uint256[]) public amounts;

    constructor(address doubleProxy, address ethItemOrchestrator, string memory name, string memory symbol, string memory uri) {
        _doubleProxy = doubleProxy;
        (collection,) = IEthItemOrchestrator(ethItemOrchestrator).createNative(abi.encodeWithSignature("init(string,string,bool,string,address,bytes)", name, symbol, true, uri, address(this), ""), "");
    }

    modifier onlyDFO() {
        require(IMVDFunctionalitiesManager(IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDFunctionalitiesManagerAddress()).isAuthorizedFunctionality(msg.sender), "Unauthorized");
        _;
    }

    function setDoubleProxy(address newDoubleProxy) public override onlyDFO {
        _doubleProxy = newDoubleProxy;
    }

    function setCollectionUri(string memory uri) public override onlyDFO {
        INativeV1(collection).setUri(uri);
    }

    function info(uint256 objectId, uint256 value) public override view returns(address[] memory _tokens, uint256[] memory _amounts) {
        uint256 amount = value == 0 ? 1e18 : value;
        _tokens = tokens[objectId];
        _amounts = new uint256[](_tokens.length);
        for(uint256 i = 0; i < _amounts.length; i++) {
            _amounts[i] = (amounts[objectId][i] * amount) / 1e18;
        }
    }

    function mint(string memory name, string memory symbol, string memory uri, address[] memory _tokens, uint256[] memory _amounts, uint256 value, address receiver) public override payable returns(uint256 objectId, address interoperableInterfaceAddress) {
        require(_tokens.length > 0 && _tokens.length == _amounts.length, "invalid length");
        for(uint256 i = 0; i < _tokens.length; i++) {
            require(!_temporaryIndex[_tokens[i]], "already done");
            require(_amounts[i] > 0, "amount");
            _temporaryIndex[_tokens[i]] = true;
            if(value > 0) {
                uint256 tokenValue = (_amounts[i] * value) / 1e18;
                require(tokenValue > 0, "Insufficient balance");
                if(_tokens[i] == address(0)) {
                    require(msg.value == tokenValue, "insufficient eth");
                } else {
                    _safeTransferFrom(_tokens[i], msg.sender, address(this), tokenValue);
                }
            }
        }
        require(_temporaryIndex[address(0)] || msg.value == 0, "eth not involved");
        INativeV1 theCollection = INativeV1(collection);
        (objectId, interoperableInterfaceAddress) = theCollection.mint(value == 0 ? 1e18 : value, name, symbol, uri, true);
        tokens[objectId] = _tokens;
        amounts[objectId] = _amounts;
        if(value == 0) {
            theCollection.burn(objectId, theCollection.balanceOf(address(this), objectId));
        } else {
            _safeTransfer(interoperableInterfaceAddress, receiver == address(0) ? msg.sender : receiver, theCollection.toInteroperableInterfaceAmount(objectId, theCollection.balanceOf(address(this), objectId)));
        }
        for(uint256 i = 0; i < _tokens.length; i++) {
            delete _temporaryIndex[_tokens[i]];
            emit NewIndex(objectId, interoperableInterfaceAddress, _tokens[i], _amounts[i]);
        }
    }

    function mint(uint256 objectId, uint256 value, address receiver) public override payable {
        require(value > 0, "value");
        bool ethInvolved = false;
        for(uint256 i = 0; i < tokens[objectId].length; i++) {
            uint256 tokenValue = (amounts[objectId][i] * value) / 1e18;
            require(tokenValue > 0, "Insufficient balance");
            if(tokens[objectId][i] == address(0)) {
                ethInvolved = true;
                 require(msg.value == tokenValue, "insufficient eth");
            } else {
                _safeTransferFrom(tokens[objectId][i], msg.sender, address(this), tokenValue);
            }
        }
        require(ethInvolved || msg.value == 0, "eth not involved");
        INativeV1 theCollection = INativeV1(collection);
        theCollection.mint(objectId, value);
        _safeTransfer(address(theCollection.asInteroperable(objectId)), receiver == address(0) ? msg.sender : receiver, theCollection.toInteroperableInterfaceAmount(objectId, theCollection.balanceOf(address(this), objectId)));
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
            require(msg.sender == collection, "Only Index collection allowed here");
            _onSingleReceived(from, id, value, data);
            return this.onERC1155Received.selector;
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

        require(msg.sender == collection, "Only Index collection allowed here");
        bytes[] memory payloads = abi.decode(data, (bytes[]));
        require(payloads.length == ids.length, "Wrong payloads length");
        for(uint256 i = 0; i < ids.length; i++) {
            _onSingleReceived(from, ids[i], values[i], payloads[i]);
        }
        return this.onERC1155BatchReceived.selector;
    }

    function _onSingleReceived(
        address from,
        uint256 objectId,
        uint256 value,
        bytes memory data) private {
            address receiver = data.length == 0 ? from : abi.decode(data, (address));
            receiver = receiver == address(0) ? from : receiver;
            INativeV1 theCollection = INativeV1(collection);
            theCollection.burn(objectId, value);
            for(uint256 i = 0; i < tokens[objectId].length; i++) {
                uint256 tokenValue = (amounts[objectId][i] * value) / 1e18;
                if(tokens[objectId][i] == address(0)) {
                    (bool result,) = receiver.call{value:tokenValue}("");
                    require(result, "ETH transfer failed");
                } else {
                    _safeTransfer(tokens[objectId][i], receiver, tokenValue);
                }
            }
    }

    function _safeApprove(address erc20TokenAddress, address to, uint256 value) internal {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).approve.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'APPROVE_FAILED');
    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) internal {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFER_FAILED');
    }

    function _safeTransferFrom(address erc20TokenAddress, address from, address to, uint256 value) private {
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