//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "../IPresto.sol";
import "../../amm-aggregator/common/IAMM.sol";
import "../../index/IIndex.sol";
import "../util/ERC1155Receiver.sol";
import "../util/INativeV1.sol";

contract IndexPresto is ERC1155Receiver {

    mapping(address => uint256) private _tokenIndex;
    address[] private _tokensToTransfer;
    uint256[] private _tokenAmounts;
    PrestoOperation[] private _operations;

    receive() external payable {
    }

    function mint(
        address prestoAddress,
        PrestoOperation[] memory operations,
        address indexAddress,
        bytes memory indexData
    ) public payable returns(uint256 objectId, address interoperableInterfaceAddress) {
        uint256 eth = _transferToMeAndCheckAllowance(operations, prestoAddress);
        IPresto(prestoAddress).execute{value : eth}(_operations);
        address[] memory tokenAddresses;
        (objectId, interoperableInterfaceAddress, tokenAddresses) = _mint(indexAddress, indexData);
        _flushAndClear(interoperableInterfaceAddress, tokenAddresses, msg.sender);
    }

    function mint(
        address prestoAddress,
        PrestoOperation[] memory operations,
        address indexAddress,
        uint256 objectId, uint256 value, address receiver) public payable {
        uint256 eth = _transferToMeAndCheckAllowance(operations, prestoAddress);
        IPresto(prestoAddress).execute{value : eth}(_operations);
        (address[] memory tokenAddresses, uint256[] memory amounts) = IIndex(indexAddress).info(objectId, value);
        _approve(indexAddress, tokenAddresses, amounts);
        IIndex(indexAddress).mint{value : _balanceOf(address(0))}(objectId, value, receiver);
        _flushAndClear(address(INativeV1(IIndex(indexAddress).collection()).asInteroperable(objectId)), tokenAddresses, msg.sender);
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
            (address prestoAddress, PrestoOperation[] memory operations, bytes memory payload) = abi.decode(data, (address, PrestoOperation[], bytes));
            INativeV1(msg.sender).safeTransferFrom(address(this), INativeV1(msg.sender).extension(), id, value, payload);
            uint256[] memory ids = new uint256[](1);
            ids[0] = id;
            _afterBurn(prestoAddress, operations, ids, from);
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
            (address prestoAddress, PrestoOperation[] memory operations, bytes memory payload) = abi.decode(data, (address, PrestoOperation[], bytes));
            INativeV1(msg.sender).safeBatchTransferFrom(address(this), INativeV1(msg.sender).extension(), ids, values, payload);
            _afterBurn(prestoAddress, operations, ids, from);
            return this.onERC1155BatchReceived.selector;
    }

    function _afterBurn(
        address prestoAddress,
        PrestoOperation[] memory operations,
        uint256[] memory ids,
        address from) private {
            IPresto(prestoAddress).execute{value : _collectTokensAndCheckAllowance(operations, prestoAddress)}(operations);
            for(uint256 i = 0; i < ids.length; i++) {
                _collectTokenData(address(INativeV1(msg.sender).asInteroperable(ids[i])), 1);
            }
            _flushAndClear(address(0), new address[](0), from);
    }

    function _mint(address indexAddress, bytes memory indexData) private returns(uint256 objectId, address interoperableInterfaceAddress, address[] memory tokenAddresses) {
        (string memory name, string memory symbol, string memory uri, address[] memory _tokens, uint256[] memory _amounts, uint256 value, address receiver) = abi.decode(indexData, (string, string, string, address[], uint256[], uint256, address));
        _approve(indexAddress, tokenAddresses = _tokens, new uint256[](0));
        (objectId, interoperableInterfaceAddress) = IIndex(indexAddress).mint{value : _balanceOf(address(0))}(name, symbol, uri, _tokens, _amounts, value, receiver);
    }

    function _approve(address indexAddress, address[] memory tokenAddresses, uint256[] memory amounts) private {
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            _safeApprove(tokenAddresses[i], indexAddress, amounts.length > 0 ? amounts[i] : _balanceOf(tokenAddresses[i]));
        }
    }

    function _flushAndClear(address indexInteroperableInterfaceAddress, address[] memory tokenAddresses, address receiver) private {
        _safeTransfer(indexInteroperableInterfaceAddress, receiver, _balanceOf(indexInteroperableInterfaceAddress));
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            if(_tokensToTransfer.length == 0 || _tokensToTransfer[_tokenIndex[tokenAddresses[i]]] != tokenAddresses[i]) {
                _safeTransfer(tokenAddresses[i], receiver, _balanceOf(tokenAddresses[i]));
            }
        }
        if(_tokensToTransfer.length == 0 || _tokensToTransfer[_tokenIndex[address(0)]] != address(0)) {
            _safeTransfer(address(0), receiver, address(this).balance);
        }
        _flushAndClear();
    }

    function _transferToMeAndCheckAllowance(PrestoOperation[] memory operations, address operator) private returns (uint256 eth) {
        eth = _collectTokensAndCheckAllowance(operations, operator);
        for(uint256 i = 0; i < _tokensToTransfer.length; i++) {
            if(_tokensToTransfer[i] == address(0)) {
                require(msg.value == _tokenAmounts[i], "Incorrect ETH value");
            } else {
                _safeTransferFrom(_tokensToTransfer[i], msg.sender, address(this), _tokenAmounts[i]);
            }
        }
    }

    function _collectTokensAndCheckAllowance(PrestoOperation[] memory operations, address operator) private returns (uint256 eth) {
        for(uint256 i = 0; i < operations.length; i++) {
            PrestoOperation memory operation = operations[i];
            require(operation.ammPlugin == address(0) || operation.liquidityPoolAddresses.length > 0, "AddLiquidity not allowed"); 
            _collectTokenData(operation.ammPlugin != address(0) && operation.enterInETH ? address(0) : operation.inputTokenAddress, operation.inputTokenAmount);
            if(operation.ammPlugin != address(0)) {
                _operations.push(operation);
                if(operation.inputTokenAddress == address(0) || operation.enterInETH) {
                    eth += operation.inputTokenAmount;
                }
            }
        }
        for(uint256 i = 0 ; i < _tokensToTransfer.length; i++) {
            if(_tokensToTransfer[i] != address(0)) {
                _safeApprove(_tokensToTransfer[i], operator, _tokenAmounts[i]);
            }
        }
    }

    function _collectTokenData(address inputTokenAddress, uint256 inputTokenAmount) private {
        if(inputTokenAmount == 0) {
            return;
        }

        uint256 position = _tokenIndex[inputTokenAddress];

        if(_tokensToTransfer.length == 0 || _tokensToTransfer[position] != inputTokenAddress) {
            _tokenIndex[inputTokenAddress] = (position = _tokensToTransfer.length);
            _tokensToTransfer.push(inputTokenAddress);
            _tokenAmounts.push(0);
        }
        _tokenAmounts[position] = _tokenAmounts[position] + inputTokenAmount;
    }

    function _flushAndClear() private {
        for(uint256 i = 0; i < _tokensToTransfer.length; i++) {
            _safeTransfer(_tokensToTransfer[i], msg.sender, _balanceOf(_tokensToTransfer[i]));
            delete _tokenIndex[_tokensToTransfer[i]];
        }
        delete _tokensToTransfer;
        delete _tokenAmounts;
        delete _operations;
    }

    function _balanceOf(address tokenAddress) private view returns(uint256) {
        if(tokenAddress == address(0)) {
            return address(this).balance;
        }
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function _safeApprove(address erc20TokenAddress, address to, uint256 value) internal {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).approve.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'APPROVE_FAILED');
    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) private {
        if(value == 0) {
            return;
        }
        if(erc20TokenAddress == address(0)) {
            (bool result,) = to.call{value:value}("");
            require(result, "ETH transfer failed");
            return;
        }
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