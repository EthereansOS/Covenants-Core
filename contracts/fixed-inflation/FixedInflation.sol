//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./FixedInflationData.sol";
import "./IFixedInflationExtension.sol";
import "./util/IERC20.sol";
import "../amm-aggregator/common/IAMM.sol";

contract FixedInflation {

    uint256 public constant ONE_HUNDRED = 10000;

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
                    entryConfiguration.callerRewardPercentage
                ), operationSets[i]);
                continue;
            }
            if(entryConfiguration.remove) {
                _remove(entryConfiguration.index);
                continue;
            }
            _entries[entryConfiguration.index].blockInterval = entryConfiguration.blockInterval;
            _entries[entryConfiguration.index].callerRewardPercentage = entryConfiguration.callerRewardPercentage;
            _setOperations(entryConfiguration.index, operationSets[i]);
        }
    }

    function nextBlock(uint256 i) public view returns(uint256) {
        return _entries[i].lastBlock == 0 ? block.number : (_entries[i].lastBlock + _entries[i].blockInterval);
    }

    function call(uint256[][] memory indexes) public {
        require(indexes.length > 0, "Invalid input data");
        for(uint256 i = 0; i < indexes.length; i++) {
            require(_entriesLength > indexes[i][0], "Invalid index");
            require(block.number >= nextBlock(indexes[i][0]), "Too early to call index");
            FixedInflationEntry storage fixedInflationEntry = _entries[indexes[i][0]];
            fixedInflationEntry.lastBlock = block.number;
            _collectFixedInflationOperationSetTokens(_operations[indexes[i][0]]);
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
        return (_tokenTotalSupply[tokenAddress] * ((tokenAmount * 1e18) / ONE_HUNDRED)) / 1e18;
    }

    function _collectFixedInflationOperationSetTokens(FixedInflationOperation[] memory operations) private {
        for(uint256 i = 0; i < operations.length; i++) {
            FixedInflationOperation memory operation = operations[i];
            _collectTokenData(operation.inputToken);
        }
    }

    function _call(FixedInflationEntry memory fixedInflationEntry, FixedInflationOperation[] memory operations, bool earnByInput, address rewardReceiver) private {
        for(uint256 i = 0 ; i < operations.length; i++) {
            FixedInflationOperation memory operation = operations[i];
            if(operation.ammPlugin == address(0)) {
                _transferTo(operation.inputToken.tokenAddress, _calculateTokenAmount(operation.inputToken), rewardReceiver, fixedInflationEntry.callerRewardPercentage, operation.receivers, operation.receiversPercentages);
            } else {
                _swap(operation, rewardReceiver, fixedInflationEntry.callerRewardPercentage, earnByInput);
            }
        }
    }

    function _swap(FixedInflationOperation memory operation, address rewardReceiver, uint256 callerRewardPercentage, bool earnByInput) private {
        uint256 amountIn = _calculateTokenAmount(operation.inputToken);

        uint256 inputReward = earnByInput ? _calculateRewardPercentage(amountIn, callerRewardPercentage) : 0;

        address outputToken = operation.swapPath[operation.swapPath.length - 1];

        LiquidityToSwap memory liquidityToSwap = LiquidityToSwap(
            operation.inputToken.tokenAddress == address(0),
            outputToken == address(0),
            operation.liquidityPoolAddresses,
            operation.swapPath,
            operation.inputToken.tokenAddress,
            amountIn - inputReward,
            address(this)
        );

        uint256 amountOut;
        if(liquidityToSwap.enterInETH) {
            amountOut = IAMM(operation.ammPlugin).swapLiquidity{value : amountIn}(liquidityToSwap);
        } else {
            amountOut = IAMM(operation.ammPlugin).swapLiquidity(liquidityToSwap);
        }

        if(earnByInput) {
            _transferTo(operation.inputToken.tokenAddress, rewardReceiver, inputReward);
        }
        _transferTo(outputToken, amountOut, earnByInput ? address(0) : rewardReceiver, earnByInput ? 0 : callerRewardPercentage, operation.receivers, operation.receiversPercentages);
    }

    function _calculateRewardPercentage(uint256 totalAmount, uint256 rewardPercentage) private pure returns (uint256) {
        return (totalAmount * ((rewardPercentage * 1e18) / ONE_HUNDRED)) / 1e18;
    }

    function _transferTo(address erc20TokenAddress, uint256 totalAmount, address rewardReceiver, uint256 callerRewardPercentage, address[] memory receivers, uint256[] memory receiversPercentages) private {
        uint256 availableAmount = totalAmount;

        uint256 currentPartialAmount = rewardReceiver == address(0) ? 0 : _calculateRewardPercentage(totalAmount, callerRewardPercentage);
        _transferTo(erc20TokenAddress, rewardReceiver, currentPartialAmount);
        availableAmount -= currentPartialAmount;

        for(uint256 i = 0; i < receiversPercentages.length; i++) {
            _transferTo(erc20TokenAddress, receivers[i], currentPartialAmount = _calculateRewardPercentage(totalAmount, receiversPercentages[i]));
            availableAmount -= currentPartialAmount;
        }

        _transferTo(erc20TokenAddress, receivers[receivers.length - 1], availableAmount);
    }

    function _transferTo(address erc20TokenAddress, address to, uint256 value) private {
        if(value == 0) {
            return;
        }
        if(erc20TokenAddress == address(0)) {
            payable(to).transfer(value);
            return;
        }
        _safeTransfer(erc20TokenAddress, to, value);
    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) private {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }

    function _clearVars() private {
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
        _setOperations(_entriesLength - 1, operations);
    }

    function _setOperations(uint256 index, FixedInflationOperation[] memory operations) private {
        require(index < _entriesLength, "Invalid length");
        delete _operations[index];
        for(uint256 i = 0; i < operations.length; i++) {
            FixedInflationOperation memory operation = operations[i];
            require(operation.receivers.length > 0, "No receivers");
            require(operation.receiversPercentages.length == (operation.receivers.length - 1), "Percentages must be less than receivers");
            uint256 percentage = _entries[index].callerRewardPercentage;
            for(uint256 j = 0; j < operation.receiversPercentages.length; j++) {
                percentage += operation.receiversPercentages[j];
                require(operation.receivers[j] != address(0), "Void receiver");
            }
            require(operation.receivers[operation.receivers.length - 1] != address(0), "Void receiver");
            require(percentage < ONE_HUNDRED, "More than one hundred");
            _operations[index].push(operations[i]);
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