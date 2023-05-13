//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/IAMM.sol";
import { IERC20Full, Bytes32Utilities, TransferUtilities, Uint256Utilities, AddressUtilities } from "@ethereansos/swissknife/contracts/lib/GeneralUtilities.sol";
import "../../util/IERC721.sol";
import "../../util/IERC1155.sol";

library NFTLibrary {

    function retrieveLiquidityPoolIdAndApprove(AMM.ProcessedLiquidityPoolParams memory processedLiquidityPoolParams, uint256 liquidityPoolTokenType, address liquidityPoolCollectionAddress) public {
        if(liquidityPoolTokenType == 1155) {
            IERC1155(liquidityPoolCollectionAddress).safeTransferFrom(msg.sender, address(this), processedLiquidityPoolParams.liquidityPoolId, processedLiquidityPoolParams.liquidityPoolAmount, "");
            if(processedLiquidityPoolParams.liquidityPoolOperator != address(0)) {
                IERC1155(liquidityPoolCollectionAddress).setApprovalForAll(processedLiquidityPoolParams.liquidityPoolOperator, true);
            }
        } else {
            _transfer721(msg.sender, address(this), liquidityPoolCollectionAddress, processedLiquidityPoolParams.liquidityPoolId, liquidityPoolTokenType);
            if(processedLiquidityPoolParams.liquidityPoolOperator != address(0)) {
                IERC721(liquidityPoolCollectionAddress).setApprovalForAll(processedLiquidityPoolParams.liquidityPoolOperator, true);
            }
        }
    }

    function retrieveLiquidityPoolIdsAndApprove(AMM.ProcessedLiquidityPoolParams[] memory processedLiquidityPoolParamsArray, uint256 liquidityPoolTokenType, address liquidityPoolCollectionAddress) external {
        for(uint256 i = 0; i < processedLiquidityPoolParamsArray.length; i++) {
            retrieveLiquidityPoolIdAndApprove(processedLiquidityPoolParamsArray[i], liquidityPoolTokenType, liquidityPoolCollectionAddress);
        }
    }

    function flushBack(uint256 liquidityPoolId, uint256 liquidityPoolTokenType, address liquidityPoolCollectionAddress) external {
        if(liquidityPoolTokenType == 1155) {
            uint256 balance = IERC1155(liquidityPoolCollectionAddress).balanceOf(address(this), liquidityPoolId);
            if(balance > 0) {
                IERC1155(liquidityPoolCollectionAddress).safeTransferFrom(address(this), msg.sender, liquidityPoolId, balance, "");
            }
        } else {
            if(IERC721(liquidityPoolCollectionAddress).ownerOf(liquidityPoolId) == address(this)) {
                _transfer721(address(this), msg.sender, liquidityPoolCollectionAddress, liquidityPoolId, liquidityPoolTokenType);
            }
        }
    }

    function _transfer721(address from, address to, address tokenAddress, uint256 tokenId, uint256 tokenType) private {
        if(tokenType == 721) {
            IERC721(tokenAddress).transferFrom(from, to, tokenId);
            return;
        }
        if(tokenType == 722) {
            IERC721(tokenAddress).safeTransferFrom(from, to, tokenId);
            return;
        }
        IERC721(tokenAddress).safeTransferFrom(from, to, tokenId, "");
    }
}

abstract contract AMM is IAMM, IERC721Receiver, IERC1155Receiver {
    using Bytes32Utilities for bytes32;
    using TransferUtilities for address;
    using AddressUtilities for address;
    using Uint256Utilities for uint256;

    struct ProcessedLiquidityPoolParams {
        uint256 liquidityPoolId;
        uint256 liquidityPoolAmount;
        address[] liquidityPoolTokens;
        uint256[] tokensAmounts;
        bool involvingETH;
        bytes additionalData;
        uint256[] amountsMin;
        address receiver;
        uint256 deadline;
        address liquidityPoolOperator;
    }

    struct ProcessedSwapParams {
        bool enterInETH;
        bool exitInETH;
        uint256[] liquidityPoolIds;
        address[] path;
        address inputToken;
        uint256 amount;
        bytes additionalData;
        uint256 minAmount;
        address receiver;
        uint256 deadline;
        address liquidityPoolOperator;
    }

    struct InternalStorage {
        address[] tokens;
        mapping(address => uint256) amount;
        address operator;
    }

    InternalStorage private _internalStorage;

    address internal _this = address(this);
    string internal _name;
    uint256 internal _version;
    address internal _ethereumAddress;
    uint256 internal _maxTokensPerLiquidityPool;
    bool internal _hasUniqueLiquidityPools;
    uint256 internal _liquidityPoolTokenType;//13 means Assets, 20 mean ERC-20, 1155 means ERC-1155, 721 means ERC-721 transferred through transferFrom, 722 means ERC-721 transferred through safeTransferFrom without payload, 723 means ERC-721 transferred through safeTransferFrom with payload
    address internal _liquidityPoolCollectionAddress;

    constructor(string memory name, uint256 version, address ethereumAddress, uint256 maxTokensPerLiquidityPool, bool hasUniqueLiquidityPools, uint256 liquidityPoolTokenType, address liquidityPoolCollectionAddress) {
        _name = name;
        _version = version;
        _ethereumAddress = ethereumAddress;
        _maxTokensPerLiquidityPool = maxTokensPerLiquidityPool;
        _hasUniqueLiquidityPools = hasUniqueLiquidityPools;
        _liquidityPoolTokenType = liquidityPoolTokenType;
        _liquidityPoolCollectionAddress = liquidityPoolCollectionAddress;
    }

    receive() external payable {
    }

    function onERC721Received(
        address operator,
        address,
        uint256,
        bytes calldata
    ) external view override returns (bytes4) {
        require(operator == address(this));
        return this.onERC721Received.selector;
    }

    function onERC1155Received(
        address operator,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external view override returns (bytes4) {
        require(operator == address(this));
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external view override returns (bytes4) {
        require(operator == address(this));
        return this.onERC1155BatchReceived.selector;
    }

    function info() public view override virtual returns(string memory name, uint256 version) {
        return (_name, _version);
    }

    function data() public view override virtual returns(address ethereumAddress, uint256 maxTokensPerLiquidityPool, bool hasUniqueLiquidityPools, uint256 liquidityPoolTokenType, address liquidityPoolCollectionAddress) {
        return (_ethereumAddress, _maxTokensPerLiquidityPool, _hasUniqueLiquidityPools, _liquidityPoolTokenType, _liquidityPoolCollectionAddress);
    }

    function balanceOf(uint256 liquidityPoolId, address owner) public virtual override view returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, address[] memory liquidityPoolTokens) {
        (liquidityPoolTokenAmounts, liquidityPoolTokens) = byLiquidityPoolAmount(liquidityPoolId, liquidityPoolAmount = IERC20Full(_toAddress(liquidityPoolId)).balanceOf(owner));
    }

    function byPercentage(uint256 liquidityPoolId, uint256 numerator, uint256 denominator) public virtual override view returns (uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, address[] memory liquidityPoolTokens) {
        (liquidityPoolAmount, liquidityPoolTokenAmounts, liquidityPoolTokens) = this.byLiquidityPool(liquidityPoolId);

        liquidityPoolAmount = _calculatePercentage(liquidityPoolAmount, numerator, denominator);

        for(uint256 i = 0; i < liquidityPoolTokenAmounts.length; i++) {
            liquidityPoolTokenAmounts[i] = _calculatePercentage(liquidityPoolTokenAmounts[i], numerator, denominator);
        }
    }

    function byLiquidityPoolAmount(uint256 liquidityPoolId, uint256 liquidityPoolAmount) public virtual override view returns(uint256[] memory liquidityPoolTokenAmounts, address[] memory liquidityPoolTokens) {

        uint256 numerator = liquidityPoolAmount;
        uint256 denominator;

        (denominator, liquidityPoolTokenAmounts, liquidityPoolTokens) = this.byLiquidityPool(liquidityPoolId);

        for(uint256 i = 0; i < liquidityPoolTokenAmounts.length; i++) {
            liquidityPoolTokenAmounts[i] = _calculatePercentage(liquidityPoolTokenAmounts[i], numerator, denominator);
        }
    }

    function byTokenAmount(uint256 liquidityPoolId, address tokenAddress, uint256 tokenAmount) public virtual override view returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, address[] memory liquidityPoolTokens) {

        (liquidityPoolAmount, liquidityPoolTokenAmounts, liquidityPoolTokens) = this.byLiquidityPool(liquidityPoolId);

        uint256 numerator = tokenAmount;
        uint256 denominator;

        for(uint256 i = 0; i < liquidityPoolTokens.length; i++) {
            if(liquidityPoolTokens[i] == tokenAddress) {
                denominator =  liquidityPoolTokenAmounts[i];
                break;
            }
        }

        liquidityPoolAmount = _calculatePercentage(liquidityPoolAmount, numerator, denominator);

        for(uint256 i = 0; i < liquidityPoolTokenAmounts.length; i++) {
            liquidityPoolTokenAmounts[i] = _calculatePercentage(liquidityPoolTokenAmounts[i], numerator, denominator);
        }
    }

    function addLiquidityEnsuringPool(LiquidityPoolCreationParams memory liquidityPoolCreationParams) public payable returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, uint256 liquidityPoolId, address[] memory liquidityPoolTokens) {
        require(liquidityPoolCreationParams.tokenAddresses.length > 1 && liquidityPoolCreationParams.tokenAddresses.length == liquidityPoolCreationParams.amounts.length && (_maxTokensPerLiquidityPool == 0 || liquidityPoolCreationParams.tokenAddresses.length == _maxTokensPerLiquidityPool), "Invalid length");
        if(_hasUniqueLiquidityPools) {
            (liquidityPoolAmount, liquidityPoolTokenAmounts, liquidityPoolId, liquidityPoolTokens) = this.byTokens(liquidityPoolCreationParams.tokenAddresses, liquidityPoolCreationParams.additionalData);
                if(liquidityPoolId != 0) {
                (liquidityPoolAmount, liquidityPoolTokenAmounts, liquidityPoolId, liquidityPoolTokens) = addLiquidity(LiquidityPoolParams(
                    liquidityPoolId,
                    liquidityPoolCreationParams.amounts[0],
                    liquidityPoolCreationParams.tokenAddresses[0],
                    false,
                    liquidityPoolCreationParams.involvingETH,
                    liquidityPoolCreationParams.additionalData,
                    liquidityPoolCreationParams.amountsMin,
                    liquidityPoolCreationParams.receiver,
                    liquidityPoolCreationParams.deadline
                ));
                return (liquidityPoolAmount, liquidityPoolTokenAmounts, liquidityPoolId, liquidityPoolTokens);
            }
        }
        address liquidityPoolCreator = _getLiquidityPoolCreationOperator(liquidityPoolCreationParams.tokenAddresses, liquidityPoolCreationParams.amounts, liquidityPoolCreationParams.involvingETH, liquidityPoolCreationParams.additionalData);
        _transferToMeAndApprove(liquidityPoolCreationParams.tokenAddresses, liquidityPoolCreationParams.amounts, liquidityPoolCreator, liquidityPoolCreationParams.involvingETH);
        (liquidityPoolAmount, liquidityPoolTokenAmounts, liquidityPoolId, liquidityPoolTokens) = _createLiquidityPoolAndAddLiquidity(liquidityPoolCreationParams);
        _checkAmountsMin(liquidityPoolTokenAmounts, liquidityPoolCreationParams.amountsMin);
        require(block.timestamp < liquidityPoolCreationParams.deadline, "deadline");
        emit NewLiquidityPool(liquidityPoolId);
        _flushBack(liquidityPoolCreationParams.tokenAddresses, liquidityPoolId, liquidityPoolCreationParams.involvingETH, _liquidityPoolTokenType);
    }

    function addLiquidity(LiquidityPoolParams memory liquidityPoolParams) public override virtual payable returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, uint256 liquidityPoolId, address[] memory liquidityPoolTokens) {
        ProcessedLiquidityPoolParams memory processedLiquidityPoolParams = _processLiquidityPoolParams(liquidityPoolParams);
        _transferToMeAndApprove(liquidityPoolTokens = processedLiquidityPoolParams.liquidityPoolTokens, processedLiquidityPoolParams.tokensAmounts, processedLiquidityPoolParams.liquidityPoolOperator, liquidityPoolParams.involvingETH);
        (liquidityPoolAmount, liquidityPoolTokenAmounts, liquidityPoolId) = _addLiquidity(processedLiquidityPoolParams);
        _checkAmountsMin(liquidityPoolTokenAmounts, processedLiquidityPoolParams.amountsMin);
        require(block.timestamp < processedLiquidityPoolParams.deadline, "deadline");
        processedLiquidityPoolParams.liquidityPoolId = liquidityPoolId;
        _flushBack(processedLiquidityPoolParams.liquidityPoolTokens, processedLiquidityPoolParams.liquidityPoolId, processedLiquidityPoolParams.involvingETH, _liquidityPoolTokenType);
    }

    function addLiquidityBatch(LiquidityPoolParams[] memory liquidityPoolParams) public override virtual payable returns(uint256[] memory liquidityPoolAmounts, uint256[][] memory liquidityPoolTokenAmounts, uint256[] memory liquidityPoolIds, address[][] memory liquidityPoolTokens) {
        liquidityPoolAmounts = new uint256[](liquidityPoolParams.length);
        liquidityPoolTokenAmounts = new uint256[][](liquidityPoolParams.length);
        liquidityPoolIds = new uint256[](liquidityPoolParams.length);
        liquidityPoolTokens = new address[][](liquidityPoolParams.length);
        ProcessedLiquidityPoolParams[] memory processedLiquidityPoolDataArray = new ProcessedLiquidityPoolParams[](liquidityPoolParams.length);
        for(uint256 i = 0; i < liquidityPoolParams.length; i++) {
            liquidityPoolTokens[i] = (processedLiquidityPoolDataArray[i] = _processLiquidityPoolParams(liquidityPoolParams[i])).liquidityPoolTokens;
            for(uint256 z = 0; z < liquidityPoolTokens[i].length; z++) {
                _collect(liquidityPoolTokens[i][z], processedLiquidityPoolDataArray[i].tokensAmounts[z], processedLiquidityPoolDataArray[i].liquidityPoolOperator, processedLiquidityPoolDataArray[i].involvingETH);
            }
        }
        _transferToMeApproveAndClear();
        for(uint256 i = 0; i < processedLiquidityPoolDataArray.length; i++) {
            (liquidityPoolAmounts[i], liquidityPoolTokenAmounts[i], liquidityPoolIds[i]) = _addLiquidity(processedLiquidityPoolDataArray[i]);
            processedLiquidityPoolDataArray[i].liquidityPoolId = liquidityPoolIds[i];
            _checkAmountsMin(liquidityPoolTokenAmounts[i], processedLiquidityPoolDataArray[i].amountsMin);
            require(block.timestamp < processedLiquidityPoolDataArray[i].deadline, "deadline");
        }
        _flushBack(processedLiquidityPoolDataArray);
    }

    function removeLiquidity(LiquidityPoolParams memory liquidityPoolParams) public override virtual returns(uint256 removedLiquidityPoolAmount, uint256[] memory removedLiquidityPoolTokenAmounts, address[] memory liquidityPoolTokens) {
        ProcessedLiquidityPoolParams memory processedLiquidityPoolParams = _processLiquidityPoolParams(liquidityPoolParams);
        liquidityPoolTokens = processedLiquidityPoolParams.liquidityPoolTokens;
        _retrieveLiquidityPoolIdAndApprove(processedLiquidityPoolParams);
        (removedLiquidityPoolAmount, removedLiquidityPoolTokenAmounts) = _removeLiquidity(processedLiquidityPoolParams);
        _checkAmountsMin(removedLiquidityPoolTokenAmounts, processedLiquidityPoolParams.amountsMin);
        require(block.timestamp < processedLiquidityPoolParams.deadline, "deadline");
        _flushBack(processedLiquidityPoolParams.liquidityPoolTokens, processedLiquidityPoolParams.liquidityPoolId, processedLiquidityPoolParams.involvingETH, _liquidityPoolTokenType);
    }

    function removeLiquidityBatch(LiquidityPoolParams[] memory liquidityPoolParams) public override virtual returns(uint256[] memory removedLiquidityPoolAmounts, uint256[][] memory removedLiquidityPoolTokenAmounts, address[][] memory liquidityPoolTokens) {
        removedLiquidityPoolAmounts = new uint256[](liquidityPoolParams.length);
        removedLiquidityPoolTokenAmounts = new uint256[][](liquidityPoolParams.length);
        liquidityPoolTokens = new address[][](liquidityPoolParams.length);
        ProcessedLiquidityPoolParams[] memory processedLiquidityPoolParamsArray = new ProcessedLiquidityPoolParams[](liquidityPoolParams.length);
        for(uint256 i = 0; i < liquidityPoolParams.length; i++) {
            processedLiquidityPoolParamsArray[i] = _processLiquidityPoolParams(liquidityPoolParams[i]);
            liquidityPoolTokens[i] = processedLiquidityPoolParamsArray[i].liquidityPoolTokens;
        }
        _retrieveLiquidityPoolIdsAndApprove(processedLiquidityPoolParamsArray);
        for(uint256 i = 0; i < processedLiquidityPoolParamsArray.length; i++) {
            (removedLiquidityPoolAmounts[i], removedLiquidityPoolTokenAmounts[i]) = _removeLiquidity(processedLiquidityPoolParamsArray[i]);
            _checkAmountsMin(removedLiquidityPoolTokenAmounts[i], processedLiquidityPoolParamsArray[i].amountsMin);
            require(block.timestamp < processedLiquidityPoolParamsArray[i].deadline, "deadline");
        }
        _flushBack(processedLiquidityPoolParamsArray);
    }

    function getSwapCounterValue(uint256 amount, bool amountIsLiquidityPool, bool amountIsOutput, uint256[] calldata liquidityPoolIds, address[] calldata path) view external returns(uint256) {
        require(path.length > 1 && liquidityPoolIds.length == (path.length - 1), "data");
        uint256 realAmount = amount;
        if(amountIsLiquidityPool) {
            realAmount = 0;
            (uint256[] memory realValues, address[] memory tokens) = byLiquidityPoolAmount(liquidityPoolIds[amountIsOutput ? liquidityPoolIds.length - 1 : 0], amount);
            address tokenAddress = path[amountIsOutput ? path.length - 1 : 0];
            for(uint256 i = 0; i < tokens.length; i++) {
                if(tokens[i] == tokenAddress) {
                    realAmount = realValues[i];
                    break;
                }
            }
        }
        require(realAmount > 0, "amount");
        return amountIsOutput ? _getSwapInput(realAmount, liquidityPoolIds, path) : _getSwapOutput(realAmount, liquidityPoolIds, path);
    }

    function swap(SwapParams memory swapParams) public override virtual payable returns(uint256 receivedValue) {
        ProcessedSwapParams memory processedSwapParams = _processSwapParams(swapParams);
        address inputTokenAddress = processedSwapParams.enterInETH && processedSwapParams.inputToken == _ethereumAddress ? address(0) : processedSwapParams.inputToken;
        _transferToMeAndApprove(inputTokenAddress.asSingleElementArray(), processedSwapParams.amount.asSingleElementArray(), processedSwapParams.liquidityPoolOperator, false);
        receivedValue = _swap(processedSwapParams);
        _checkMinAmount(receivedValue, processedSwapParams.minAmount);
        require(block.timestamp < swapParams.deadline, "deadline");
        _flushBack(processedSwapParams.enterInETH ? address(0) : processedSwapParams.inputToken);
        _flushBack(processedSwapParams.exitInETH ? address(0) : processedSwapParams.path[processedSwapParams.path.length - 1]);
    }

    function swapBatch(SwapParams[] memory swapParams) public override virtual payable returns(uint256[] memory receivedValues) {
        ProcessedSwapParams[] memory processedSwapDatas = new ProcessedSwapParams[](swapParams.length);
        receivedValues = new uint256[](swapParams.length);
        for(uint256 i = 0; i < swapParams.length; i++) {
            processedSwapDatas[i] = _processSwapParams(swapParams[i]);
            _collect(processedSwapDatas[i].inputToken, processedSwapDatas[i].amount, processedSwapDatas[i].liquidityPoolOperator, processedSwapDatas[i].enterInETH);
        }
        _transferToMeApproveAndClear();
        for(uint256 i = 0; i < swapParams.length; i++) {
            receivedValues[i] = _swap(processedSwapDatas[i]);
            _checkMinAmount(receivedValues[i], processedSwapDatas[i].minAmount);
        }
        _flushBack(processedSwapDatas);
    }

    function checkAddLiquidityAdditionalData(LiquidityPoolParams[] calldata liquidityPoolParams) external override view {
        return _checkAddLiquidityAdditionalData(_processLiquidityPoolParams(liquidityPoolParams));
    }

    function checkRemoveLiquidityAdditionalData(LiquidityPoolParams[] calldata liquidityPoolParams) external override view {
        return _checkRemoveLiquidityAdditionalData(_processLiquidityPoolParams(liquidityPoolParams));
    }

    function checkSwapAdditionalData(SwapParams[] calldata swapParams) external override view {
        return _checkSwapAdditionalData(_processSwapParams(swapParams));
    }

    function _getLiquidityPoolCreationOperator(address[] memory tokenAddresses, uint256[] memory amounts, bool involvingETH, bytes memory additionalData) internal virtual view returns(address);

    function _createLiquidityPoolAndAddLiquidity(LiquidityPoolCreationParams memory liquidityPoolCreationParams) internal virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId, address[] memory orderedTokens);

    function _getLiquidityPoolOperator(uint256 liquidityPoolId, address[] memory liquidityPoolTokens, bytes memory additionalData) internal virtual view returns(address);

    function _addLiquidity(ProcessedLiquidityPoolParams memory processedLiquidityPoolParams) internal virtual returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokens, uint256 liquidityPoolId);

    function _retrieveLiquidityPoolIdAndApprove(ProcessedLiquidityPoolParams memory processedLiquidityPoolParams) internal virtual {
        uint256 liquidityPoolTokenType = _liquidityPoolTokenType;
        if(liquidityPoolTokenType == 20) {
            return _transferToMeAndApprove( _toAddress(processedLiquidityPoolParams.liquidityPoolId).asSingleElementArray(), processedLiquidityPoolParams.liquidityPoolAmount.asSingleElementArray(), processedLiquidityPoolParams.liquidityPoolOperator, false);
        }
        NFTLibrary.retrieveLiquidityPoolIdAndApprove(processedLiquidityPoolParams, liquidityPoolTokenType, _liquidityPoolCollectionAddress);
    }

    function _retrieveLiquidityPoolIdsAndApprove(ProcessedLiquidityPoolParams[] memory processedLiquidityPoolParamsArray) internal virtual {
        uint256 liquidityPoolTokenType = _liquidityPoolTokenType;
        if(liquidityPoolTokenType != 20) {
            return NFTLibrary.retrieveLiquidityPoolIdsAndApprove(processedLiquidityPoolParamsArray, liquidityPoolTokenType, _liquidityPoolCollectionAddress);
        }
        for(uint256 i = 0; i < processedLiquidityPoolParamsArray.length; i++) {
            _collect(_toAddress(processedLiquidityPoolParamsArray[i].liquidityPoolId), processedLiquidityPoolParamsArray[i].liquidityPoolAmount, processedLiquidityPoolParamsArray[i].liquidityPoolOperator, false);
        }
        _transferToMeApproveAndClear();
    }

    function _removeLiquidity(ProcessedLiquidityPoolParams memory processedLiquidityPoolParams) internal virtual returns(uint256, uint256[] memory);

    function _getSwapOutput(uint256 amount, uint256[] memory liquidityPoolIds, address[] memory path) view internal virtual returns(uint256);

    function _getSwapInput(uint256 amount, uint256[] memory liquidityPoolIds, address[] memory path) view internal virtual returns(uint256);

    function _getSwapOperator(uint256 liquidityPoolId, address[] memory liquidityPoolTokens, bytes memory additionalData) internal virtual view returns(address);

    function _swap(ProcessedSwapParams memory processedSwapParams) internal virtual returns(uint256 outputAmount);

    function _checkAddLiquidityAdditionalData(ProcessedLiquidityPoolParams[] memory processedLiquidityPoolParams) internal virtual view;
    function _checkRemoveLiquidityAdditionalData(ProcessedLiquidityPoolParams[] memory processedLiquidityPoolParams) internal virtual view;
    function _checkSwapAdditionalData(ProcessedSwapParams[] memory processedSwapParams) internal virtual view;

    function _processLiquidityPoolParams(LiquidityPoolParams memory liquidityPoolParams) internal view returns(ProcessedLiquidityPoolParams memory) {
        require(liquidityPoolParams.amount > 0, "amount");
        uint256[] memory tokensAmounts;
        address[] memory liquidityPoolTokens;
        uint256 liquidityPoolAmount;
        if(liquidityPoolParams.amountIsLiquidityPool) {
            (tokensAmounts, liquidityPoolTokens) = byLiquidityPoolAmount(liquidityPoolParams.liquidityPoolId, liquidityPoolAmount = liquidityPoolParams.amount);
        } else {
            (liquidityPoolAmount, tokensAmounts, liquidityPoolTokens) = byTokenAmount(liquidityPoolParams.liquidityPoolId, liquidityPoolParams.tokenAddress, liquidityPoolParams.amount);
        }
        bool involvingETH = liquidityPoolParams.involvingETH;
        if(_ethereumAddress == address(0)) {
            involvingETH = false;
            for(uint256 i = 0; i < liquidityPoolTokens.length; i++) {
                if(liquidityPoolTokens[i] == address(0)) {
                    involvingETH = true;
                }
            }
        }

        return ProcessedLiquidityPoolParams(
            liquidityPoolParams.liquidityPoolId,
            liquidityPoolAmount,
            liquidityPoolTokens,
            tokensAmounts,
            involvingETH,
            liquidityPoolParams.additionalData,
            liquidityPoolParams.amountsMin,
            _receiver(liquidityPoolParams.receiver),
            liquidityPoolParams.deadline,
            _getLiquidityPoolOperator(liquidityPoolParams.liquidityPoolId, liquidityPoolTokens, liquidityPoolParams.additionalData)
        );
    }

    function _processLiquidityPoolParams(LiquidityPoolParams[] memory liquidityPoolParams) internal view returns(ProcessedLiquidityPoolParams[] memory processedLiquidityPoolParams) {
        processedLiquidityPoolParams = new ProcessedLiquidityPoolParams[](liquidityPoolParams.length);
        for(uint256 i = 0; i < processedLiquidityPoolParams.length; i++) {
            processedLiquidityPoolParams[i] = _processLiquidityPoolParams(liquidityPoolParams[i]);
        }
    }

    function _processSwapParams(SwapParams memory swapParams) internal view returns(ProcessedSwapParams memory) {
        require(swapParams.amount > 0, "amount");
        require(swapParams.path.length > 0 && swapParams.liquidityPoolIds.length == swapParams.path.length, "length");
        ( , ,address[] memory liquidityPoolTokens) = this.byLiquidityPool(swapParams.liquidityPoolIds[0]);
        return ProcessedSwapParams(
            swapParams.enterInETH && swapParams.inputToken == _ethereumAddress,
            swapParams.exitInETH && swapParams.path[swapParams.path.length - 1] == _ethereumAddress,
            swapParams.liquidityPoolIds,
            swapParams.path,
            swapParams.inputToken,
            swapParams.amount,
            swapParams.additionalData,
            swapParams.minAmount,
            _receiver(swapParams.receiver),
            swapParams.deadline,
            _getSwapOperator(swapParams.liquidityPoolIds[0], liquidityPoolTokens, swapParams.additionalData)
        );
    }

    function _receiver(address receiver) internal view returns(address) {
        return receiver != address(0) ? receiver : msg.sender;
    }

    function _processSwapParams(SwapParams[] memory swapParams) internal view returns(ProcessedSwapParams[] memory processedSwapParams) {
        processedSwapParams = new ProcessedSwapParams[](swapParams.length);
        for(uint256 i = 0; i < processedSwapParams.length; i++) {
            processedSwapParams[i] = _processSwapParams(swapParams[i]);
        }
    }

    function _transferToMeAndApprove(address[] memory tokens, uint256[] memory amounts, address operator, bool involvingETH) internal {
        require(tokens.length == amounts.length, "tokens");
        address ethereumAddress = _ethereumAddress;
        for(uint256 i = 0; i < tokens.length; i++) {
            address tokenAddress = involvingETH && tokens[i] == ethereumAddress ? address(0) : tokens[i];
            uint256 amount = amounts[i];
            if(tokenAddress == address(0)) {
                require(msg.value == amount, "ETH");
                continue;
            }
            tokenAddress.safeTransferFrom(msg.sender, address(this), amount);
            tokenAddress.safeApprove(operator, amount);
        }
    }

    function _collect(address tokenAddress, uint256 amount, address operator, bool involvingETH) private {
        require(amount != 0, "amount");
        address realTokenAddress = involvingETH && tokenAddress == _ethereumAddress ? address(0) : tokenAddress;
        _internalStorage.operator = operator;
        uint256 oldAmount = _internalStorage.amount[realTokenAddress];
        if(oldAmount == 0) {
            _internalStorage.tokens.push(realTokenAddress);
        }
        _internalStorage.amount[realTokenAddress] = oldAmount + amount;
    }

    function _transferToMeApproveAndClear() private {
        address[] memory tokens = _internalStorage.tokens;
        uint256[] memory amounts = new uint256[](tokens.length);
        for(uint256 i = 0; i < tokens.length; i++) {
            amounts[i] = _internalStorage.amount[tokens[i]];
        }
        _transferToMeAndApprove(tokens, amounts, _internalStorage.operator, false);
        delete _internalStorage;
    }

    function _flushBack(address[] memory tokenAddresses, bool alsoETH) private {
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            _flushBack(tokenAddresses[i]);
        }
        if(alsoETH) {
            _flushBack(address(0));
        }
    }

    function _flushBack(address tokenAddress) private {
        tokenAddress.safeTransfer(msg.sender, tokenAddress.balanceOf(address(this)));
    }

    function _flushBack(ProcessedLiquidityPoolParams[] memory paramsArray) private {
        uint256 liquidityPoolTokenType = _liquidityPoolTokenType;
        for(uint256 i = 0; i < paramsArray.length; i++) {
            ProcessedLiquidityPoolParams memory params = paramsArray[i];
            _flushBack(params.liquidityPoolTokens, params.liquidityPoolId, params.involvingETH, liquidityPoolTokenType);
        }
    }

    function _flushBack(ProcessedSwapParams[] memory paramsArray) private {
        for(uint256 i = 0; i < paramsArray.length; i++) {
            ProcessedSwapParams memory params = paramsArray[i];
            _flushBack(params.enterInETH ? address(0) : params.inputToken);
            _flushBack(params.exitInETH ? address(0) : params.path[params.path.length - 1]);
        }
    }

    function _flushBack(address[] memory liquidityPoolTokens, uint256 liquidityPoolId, bool involvingETH, uint256 liquidityPoolTokenType) private {
        _flushBack(liquidityPoolTokens, involvingETH);
        if(liquidityPoolTokenType == 20) {
            return _flushBack(_toAddress(liquidityPoolId));
        }
        NFTLibrary.flushBack(liquidityPoolId, liquidityPoolTokenType, _liquidityPoolCollectionAddress);
    }

    function _checkAmountsMin(uint256[] memory amounts, uint256[] memory amountsMin) internal pure {
        for(uint256 i = 0; i < amounts.length; i++) {
            _checkMinAmount(amounts[i], amountsMin[i]);
        }
    }

    function _checkMinAmount(uint256 amount, uint256 minAmount) internal pure {
        require(amount >= minAmount, "min");
    }

    function _toAddress(uint256 number) internal pure returns(address) {
        return address(uint160(number));
    }

    function _toAddresses(uint256[] memory numbers) internal pure returns(address[] memory addresses) {
        addresses = new address[](numbers.length);
        for(uint256 i = 0; i < addresses.length; i++) {
            addresses[i] = _toAddress(numbers[i]);
        }
    }

    function _toNumber(address addr) internal pure returns(uint256) {
        return uint256(uint160(addr));
    }

    function _toNumbers(address[] memory addresses) internal pure returns(uint256[] memory numbers) {
        numbers = new uint256[](addresses.length);
        for(uint256 i = 0; i < numbers.length; i++) {
            numbers[i] = _toNumber(addresses[i]);
        }
    }

    function _calculatePercentage(uint256 amount, uint256 numerator, uint256 denominator) internal virtual pure returns(uint256) {
        return (amount * numerator) / denominator;
    }

    function _reverse(address[] memory array) internal pure returns(address[] memory reverted) {
        reverted = new address[](array.length);
        for(uint256 i = 0; i < reverted.length; i++) {
            reverted[reverted.length - 1 - i] = array[i];
        }
    }

    function _reverse(uint256[] memory array) internal pure returns(uint256[] memory reverted) {
        reverted = new uint256[](array.length);
        for(uint256 i = 0; i < reverted.length; i++) {
            reverted[reverted.length - 1 - i] = array[i];
        }
    }

    function _balanceOf(address[] memory tokens) internal view returns(uint256[] memory amounts) {
        amounts = new uint256[](tokens.length);
        for(uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = tokens[i].balanceOf(address(this));
        }
    }
}