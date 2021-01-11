//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./FixedInflationData.sol";
import "./IFixedInflationExtension.sol";
import "./util/IERC20.sol";
import "../amm-aggregator/common/IAMM.sol";

contract FixedInflation {

    mapping(address => uint256) internal _tokenIndex;
    mapping(address => uint256) internal _tokenTotalSupply;
    address[] private _tokensToTransfer;
    uint256[] private _tokenAmounts;
    uint256[] private _tokenMintAmounts;
    uint256 private _tokensLength = 1;

    address public extension;

    mapping(uint256 => FixedInflationEntry) private _entries;
    mapping(uint256 => FixedInflationOperation[]) private _operations;
    uint256 private _entriesLength;

    function init(address _extension, bytes memory extensionPayload, FixedInflationEntry[] memory newEntries, FixedInflationOperation[][] memory operationSets) public returns(bytes memory extensionInitResult) {
        require(extension == address(0), "Already init");
        require(_extension != address(0), "Blank extension");
        extension = _extension;
        if(keccak256(extensionPayload) != keccak256("")) {
            bool result;
            (result, extensionInitResult) = _extension.call(extensionPayload);
            require(result, "Extension fail");
        }
        require(newEntries.length > 0 && newEntries.length == operationSets.length, "Same length > 0");
        for(uint256 i = 0; i < newEntries.length; i++) {
            _add(newEntries[i], operationSets[i]);
        }
    }

    receive() external payable {
    }

    modifier extensionOnly() {
        require(msg.sender == extension, "Unauthorized");
        _;
    }

    function entries() public view returns(FixedInflationEntry[] memory entriesArray, FixedInflationOperation[][] memory operationSets) {
        entriesArray = new FixedInflationEntry[](_entriesLength);
        operationSets = new FixedInflationOperation[][](_entriesLength);
        for(uint256 i = 0; i < _entriesLength; i++) {
            entriesArray[i] = _entries[i];
            operationSets[i] = new FixedInflationOperation[](_operations[i].length);
            for(uint256 j = 0; j < operationSets[i].length; j++) {
                operationSets[i][j] = _operations[i][j];
            }
        }
    }

    function setEntries(FixedInflationEntryConfiguration[] memory newEntries, FixedInflationOperation[][] memory operationSets) public extensionOnly {
        require(newEntries.length > 0 && newEntries.length == operationSets.length, "Same length > 0");
        for(uint256 i = 0; i < newEntries.length; i++) {
            FixedInflationEntryConfiguration memory entryConfiguration = newEntries[i];
            if(entryConfiguration.add) {
                _add(FixedInflationEntry(
                    0,
                    entryConfiguration.blockInterval,
                    entryConfiguration.ammPlugins
                ), operationSets[i]);
                continue;
            }
            if(entryConfiguration.remove) {
                _remove(entryConfiguration.index);
                continue;
            }
            _entries[entryConfiguration.index].blockInterval = entryConfiguration.blockInterval;
            delete _operations[entryConfiguration.index];
            FixedInflationOperation[] memory operations = operationSets[entryConfiguration.index];
            for(uint256 j = 0; j < operations.length; j++) {
                _operations[entryConfiguration.index].push(operations[j]);
            }
        }
    }

    function nextBlock(uint256 i) public view returns(uint256) {
        return _entries[i].lastBlock == 0 ? block.number : (_entries[i].lastBlock + _entries[i].blockInterval);
    }

    function call(uint256[][] memory indexes) public {
        require(indexes.length > 0, "Invalid input data");
        for(uint256 i = 0; i < indexes.length; i++) {
            require(_entriesLength > indexes[i][0], "Invalid index");
            require(nextBlock(indexes[i][0]) >= block.number, "Too early to call index");
            FixedInflationEntry storage fixedInflationEntry = _entries[indexes[i][0]];
            fixedInflationEntry.lastBlock = block.number;
            _collectFixedInflationOperationSetTokens(_operations[indexes[i][0]], indexes[i][1] == 1);
        }
        IFixedInflationExtension(extension).receiveTokens(_tokensToTransfer, _tokenAmounts, _tokenMintAmounts);
        for(uint256 i = 0; i < indexes.length; i++) {
            _call(_entries[indexes[i][0]], _operations[indexes[i][0]], indexes[i][1] == 1, msg.sender);
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
            _tokensToTransfer.push(tokenData.tokenAddress);
            _tokenAmounts.push(0);
            _tokenMintAmounts.push(0);
        }
        if(tokenData.amountByMint) {
            _tokenMintAmounts[position] = _tokenMintAmounts[position] + _calculateTokenAmount(tokenData);
        } else {
            _tokenAmounts[position] = _tokenAmounts[position] + _calculateTokenAmount(tokenData);
        }
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

    function _collectFixedInflationOperationSetTokens(FixedInflationOperation[] memory operations, bool byEarn) private {
        for(uint256 i = 0; i < operations.length; i++) {
            FixedInflationOperation memory operation = operations[i];
            _collectTokenData(operation.inputToken);
            if(!byEarn) {
                _collectTokenData(operation.rewardToken);
            }
        }
    }

    function _call(FixedInflationEntry memory fixedInflationEntry, FixedInflationOperation[] memory operations, bool byEarn, address rewardReceiver) private {
        for(uint256 i = 0 ; i < operations.length; i++) {
            FixedInflationOperation memory operation = operations[i];
            require(operation.receiver != address(0), "Blank receiver");
            require(!byEarn || operation.byEarnPercentage > 0, "Not byEarn");
            if(fixedInflationEntry.ammPlugins[i] == address(0)) {
                _transfer(operation, byEarn, rewardReceiver);
            } else {
                _swap(operation, fixedInflationEntry.ammPlugins[i], byEarn, rewardReceiver);
            }
        }
    }

    function _transfer(FixedInflationOperation memory operation, bool byEarn, address rewardReceiver) private {
        if(operation.inputToken.tokenAddress != address(0)) {
            _safeTransfer(operation.inputToken.tokenAddress, operation.receiver, _calculateTokenAmount(operation.inputToken));
        } else {
            payable(operation.receiver).transfer(_calculateTokenAmount(operation.inputToken));
        }
    }

    function _swap(FixedInflationOperation memory operation, address ammPlugin, bool byEarn, address rewardReceiver) private {
        uint256 amountIn = _calculateTokenAmount(operation.inputToken);
        LiquidityToSwap memory liquidityToSwap = LiquidityToSwap(
            operation.inputToken.tokenAddress == address(0),
            operation.swapPath[operation.swapPath.length - 1] == address(0),
            operation.liquidityPoolAddresses,
            operation.swapPath,
            operation.inputToken.tokenAddress,
            amountIn,
            byEarn ? address(this) : operation.receiver
        );
        uint256 amountOut;
        if(liquidityToSwap.enterInETH) {
            amountOut = IAMM(ammPlugin).swapLiquidity{value : amountIn}(liquidityToSwap);
        } else {
            amountOut = IAMM(ammPlugin).swapLiquidity(liquidityToSwap);
        }
        if(byEarn) {
            uint256 reward = (amountOut * ((operation.byEarnPercentage * 1e18) / 100)) / 1e18;
            _transferTo(operation.rewardToken.tokenAddress, rewardReceiver, reward);
            _transferTo(operation.rewardToken.tokenAddress, operation.receiver, amountOut - reward);
        } else {
            _transferTo(operation.rewardToken.tokenAddress, rewardReceiver, _calculateTokenAmount(operation.rewardToken));
            delete _tokenTotalSupply[operation.rewardToken.tokenAddress];
        }
    }

    function _transferTo(address erc20TokenAddress, address to, uint256 value) internal virtual {
        if(erc20TokenAddress == address(0)) {
            payable(to).transfer(value);
            return;
        }
        _safeTransfer(erc20TokenAddress, to, value);
    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) internal virtual {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }

    function _clearVars() internal virtual {
        _tokensLength = 1;
        for(uint256 i = 0; i < _tokensToTransfer.length; i++) {
            if(_tokensToTransfer[i] == address(0) && _tokenAmounts[i] == 0 && _tokenMintAmounts[i] == 0) {
                break;
            }
            delete _tokenIndex[address(_tokensToTransfer[i])];
            delete _tokenTotalSupply[address(_tokensToTransfer[i])];
        }
        delete _tokensToTransfer;
        delete _tokenAmounts;
        delete _tokenMintAmounts;
    }

    function _add(FixedInflationEntry memory fixedInflationEntry, FixedInflationOperation[] memory operations) private {
        _entries[_entriesLength++] = fixedInflationEntry;
        delete _operations[_entriesLength - 1];
        for(uint256 i = 0; i < operations.length; i++) {
            _operations[_entriesLength - 1].push(operations[i]);
        }
    }

    function _remove(uint256 i) private {
        require(i < _entriesLength, "Invalid length");
        _entries[i] = _entries[--_entriesLength];
        _operations[i] = _operations[_entriesLength];
        delete _entries[_entriesLength + 1];
        delete _operations[_entriesLength + 1];
    }
}