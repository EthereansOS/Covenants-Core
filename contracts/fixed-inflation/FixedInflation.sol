//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;

import "./FixedInflationData.sol";
import "./IFixedInflationExtension.sol";
import "./util/IERC20.sol";
import "../amm-aggregator/common/IAMM.sol";

contract FixedInflation {

    mapping(address => uint256) internal _tokenIndex;
    mapping(address => uint256) internal _tokenTotalSupply;
    uint256[][] private _tokensToTransfer;
    uint256 private _tokensLength = 1;

    address public extension;

    FixedInflationEntry[] public entries;

    function init(address _extension, bytes memory extensionPayload, FixedInflationEntry[] memory _entries) public returns(bytes memory extensionInitResult) {
        require(extension == address(0), "Already init");
        require(_extension != address(0), "Blank extension");
        extension = _extension;
        if(keccak256(extensionPayload) != keccak256("")) {
            bool result;
            (result, extensionInitResult) = _extension.call(extensionPayload);
            require(result, "Extension fail");
        }
        require(_entries.length > 0, "Empty entries");
        _setEntries(_entries);
    }

    receive() external payable {
    }

    modifier extensionOnly() {
        require(msg.sender == extension, "Unauthorized");
        _;
    }

    function setEntries(FixedInflationEntry[] memory _entries) public extensionOnly {
        _setEntries(_entries);
    }

    function nextBlock(uint256 i) public view returns(uint256) {
        return entries[i].lastBlock == 0 ? block.number : (entries[i].lastBlock + entries[i].blockInterval);
    }

    function entriesLength() public view returns(uint256) {
        return entries.length;
    }

    function call(uint256[] memory indexes, bool[] memory byEarn) public {
        require(indexes.length > 0 && indexes.length == byEarn.length, "Invalid input data");
        for(uint256 i = 0; i < indexes.length; i++) {
            require(entries.length > indexes[i], "Invalid index");
            require(nextBlock(indexes[i]) >= block.number, "Too early to call index");
            FixedInflationEntry storage fixedInflationEntry = entries[indexes[i]];
            fixedInflationEntry.lastBlock = block.number;
            for(uint256 j = 0; j < fixedInflationEntry.operationSets.length; j++) {
                _collectFixedInflationOperationSetTokens(fixedInflationEntry.operationSets[j], byEarn[i]);
            }
        }
        IFixedInflationExtension(extension).receiveTokens(_tokensToTransfer);
        for(uint256 i = 0; i < indexes.length; i++) {
             _call(entries[indexes[i]], byEarn[i], msg.sender);
        }
        _clearVars();
    }

    function _collectTokenData(TokenData memory tokenData) private {
        if(tokenData.amount == 0) {
            return;
        }
        uint256 position = _tokenIndex[tokenData.tokenAddress];
        if(position == 0) {
            _tokenIndex[tokenData.tokenAddress] = position = (_tokensLength++) - 1;
            _tokensToTransfer.push(new uint256[](3));
            _tokensToTransfer[position][0] = uint256(tokenData.tokenAddress);
        }
        uint256 sourceType = tokenData.amountByMint ? 1 : 2;
        _tokensToTransfer[position][sourceType] = _tokensToTransfer[position][sourceType] + _calculateTokenAmount(tokenData);
    }

    function _calculateTokenAmount(TokenData memory tokenData) private returns(uint256) {
        return _calculateTokenAmount(tokenData.tokenAddress, tokenData.amount, tokenData.amountIsPercentage);
    }

    function _calculateTokenAmount(address tokenAddress, uint256 tokenAmount, bool tokenAmountIsPercentage) private returns(uint256) {
        if(!tokenAmountIsPercentage) {
            return tokenAmount;
        }
        _tokenTotalSupply[tokenAddress] = _tokenTotalSupply[tokenAddress] != 0 ? _tokenTotalSupply[tokenAddress] : IERC20(tokenAddress).totalSupply();
        return (_tokenTotalSupply[tokenAddress] * ((tokenAmount * 1e18) / 100)) / 1e18;
    }

    function _collectFixedInflationOperationSetTokens(FixedInflationOperationSet memory operationSet, bool byEarn) private {
        for(uint256 i = 0; i < operationSet.operations.length; i++) {
            FixedInflationOperation memory operation = operationSet.operations[i];
            _collectTokenData(operation.inputToken);
            if(!byEarn) {
                _collectTokenData(operation.rewardToken);
            }
        }
    }

    function _call(FixedInflationEntry memory fixedInflationEntry, bool byEarn, address rewardReceiver) private {
        for(uint256 i = 0; i < fixedInflationEntry.operationSets.length; i++) {
            FixedInflationOperationSet memory operationSet = fixedInflationEntry.operationSets[i];
            for(uint256 j = 0 ; j < operationSet.operations.length; j++) {
                FixedInflationOperation memory operation = operationSet.operations[j];
                if(operationSet.ammPlugin == address(0)) {
                    _transfer(operation, byEarn, rewardReceiver);
                } else {
                    _swap(operation, operationSet.ammPlugin, fixedInflationEntry, byEarn, rewardReceiver);
                }
            }
        }
    }

    function _transfer(FixedInflationOperation memory operation, bool byEarn, address rewardReceiver) private {
        require(operation.receiver != address(0), "Blank receiver");
        if(operation.inputToken.tokenAddress != address(0)) {
            _safeTransfer(operation.inputToken.tokenAddress, operation.receiver, _calculateTokenAmount(operation.inputToken));
        } else {
            payable(operation.receiver).transfer(_calculateTokenAmount(operation.inputToken));
        }
    }

    function _swap(FixedInflationOperation memory operation, address ammPlugin, FixedInflationEntry memory fixedInflationEntry, bool byEarn, address rewardReceiver) private {
        LiquidityToSwap memory liquidityToSwap = LiquidityToSwap(
            operation.liquidityPoolAddress,
            0,
            true,
            false,
            new address[](0),
            _calculateTokenAmount(operation.inputToken),
            byEarn ? address(this) : operation.receiver
        );
        IAMM(ammPlugin).swapLiquidity(liquidityToSwap);
    }

    function _setEntries(FixedInflationEntry[] memory _entries) private {

    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) internal virtual {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }

    function _clearVars() internal virtual {
        _tokensLength = 1;
        for(uint256 i = 0; i < _tokensToTransfer.length; i++) {
            if(_tokensToTransfer[i][0] == 0 && _tokensToTransfer[i][1] == 0 && _tokensToTransfer[i][2] == 0) {
                break;
            }
            delete _tokenIndex[address(_tokensToTransfer[i][0])];
            delete _tokenTotalSupply[address(_tokensToTransfer[i][0])];
        }
        delete _tokensToTransfer;
    }
}