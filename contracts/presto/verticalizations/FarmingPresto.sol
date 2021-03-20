//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../IPresto.sol";
import "../util/IERC20.sol";
import "../../amm-aggregator/common/IAMM.sol";
import "../../farming/IFarmMain.sol";
import "../util/INativeV1.sol";

contract FarmingPresto {

    mapping(address => uint256) private _tokenIndex;
    address[] private _tokensToTransfer;
    uint256[] private _tokenAmounts;
    PrestoOperation[] private _operations;

    receive() external payable {
    }

    function openPosition(
        address prestoAddress,
        PrestoOperation[] memory operations,
        address farmMainAddress,
        FarmingPositionRequest memory request
    ) public payable returns(uint256 positionId) {
        request.positionOwner = request.positionOwner != address(0) ? request.positionOwner : msg.sender;
        uint256 eth = _transferToMeAndCheckAllowance(operations, prestoAddress);
        IPresto(prestoAddress).execute{value : eth}(_operations);
        IFarmMain farmMain = IFarmMain(farmMainAddress);
        (address[] memory tokenAddresses, uint256 ethereumValue) = _calculateAmountsAndApprove(farmMain, request.setupIndex, request.amount);
        positionId = farmMain.openPosition{value : ethereumValue}(request);
        _flushAndClear(tokenAddresses, msg.sender);
    }

    function addLiquidity(
        address prestoAddress,
        PrestoOperation[] memory operations,
        address farmMainAddress,
        uint256 positionId,
        FarmingPositionRequest memory request
    ) public payable {
        request.positionOwner = request.positionOwner != address(0) ? request.positionOwner : msg.sender;
        uint256 eth = _transferToMeAndCheckAllowance(operations, prestoAddress);
        IPresto(prestoAddress).execute{value : eth}(_operations);
        IFarmMain farmMain = IFarmMain(farmMainAddress);
        (address[] memory tokenAddresses, uint256 ethereumValue) = _calculateAmountsAndApprove(farmMain, farmMain.position(positionId).setupIndex, request.amount);
        farmMain.addLiquidity{value : ethereumValue}(positionId, request);
        _flushAndClear(tokenAddresses, msg.sender);
    }

    function _calculateAmountsAndApprove(IFarmMain farmMain, uint256 setupIndex, uint256 requestAmount) private returns(address[] memory tokenAddresses, uint256 ethereumValue) {
        (, FarmingSetupInfo memory setupInfo) = farmMain.setup(setupIndex);
        uint256[] memory tokensAmounts;
        (, tokensAmounts, tokenAddresses) = IAMM(setupInfo.ammPlugin).byTokenAmount(setupInfo.liquidityPoolTokenAddress, setupInfo.mainTokenAddress, requestAmount);
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            if(setupInfo.involvingETH && tokenAddresses[i] == setupInfo.ethereumAddress) {
                ethereumValue = tokensAmounts[i];
            }
            if(tokenAddresses[i] != address(0)) {
                _safeApprove(tokenAddresses[i], address(farmMain), tokensAmounts[i]);
            }
        }
    }

    function _flushAndClear(address[] memory tokenAddresses, address receiver) private {
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            if(_tokensToTransfer.length == 0 || _tokensToTransfer[_tokenIndex[tokenAddresses[i]]] != tokenAddresses[i]) {
                _safeTransfer(tokenAddresses[i], receiver, _balanceOf(tokenAddresses[i]));
            }
        }
        if(_tokensToTransfer.length == 0 || _tokensToTransfer[_tokenIndex[address(0)]] != address(0)) {
            _safeTransfer(address(0), receiver, address(this).balance);
        }
        _flushAndClear(receiver);
    }

    function _transferToMeAndCheckAllowance(PrestoOperation[] memory operations, address operator) private returns (uint256 eth) {
        eth = _collectTokensAndCheckAllowance(operations, operator);
        for(uint256 i = 0; i < _tokensToTransfer.length; i++) {
            if(_tokensToTransfer[i] == address(0)) {
                require(msg.value >= _tokenAmounts[i], "Incorrect ETH value");
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

    function _flushAndClear(address receiver) private {
        for(uint256 i = 0; i < _tokensToTransfer.length; i++) {
            _safeTransfer(_tokensToTransfer[i], receiver, _balanceOf(_tokensToTransfer[i]));
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