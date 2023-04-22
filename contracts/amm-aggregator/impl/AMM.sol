//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/IAMM.sol";
import { IERC20Full, Bytes32Utilities, TransferUtilities, Uint256Utilities, AddressUtilities } from "@ethereansos/swissknife/contracts/lib/GeneralUtilities.sol";

abstract contract AMM is IAMM {
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
        uint256[] minAmounts;
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

    address private immutable _this = address(this);
    bytes32 private immutable _name;
    uint256 private immutable _version;
    address internal immutable _ethereumAddress;
    uint256 private immutable _maxTokensPerLiquidityPool;
    bool private immutable _hasUniqueLiquidityPools;

    constructor(string memory name, uint256 version, address ethereumAddress, uint256 maxTokensPerLiquidityPool, bool hasUniqueLiquidityPools) {
        bytes memory n = abi.encodePacked(name);
        require(n.length <= 32, "name");
        _name = bytes32(n);
        _version = version;
        _ethereumAddress = ethereumAddress;
        _maxTokensPerLiquidityPool = maxTokensPerLiquidityPool;
        _hasUniqueLiquidityPools = hasUniqueLiquidityPools;
    }

    receive() external payable {
    }

    function info() public view override virtual returns(string memory name, uint256 version) {
        return (_name.asString(), _version);
    }

    function data() public view override virtual returns(address ethereumAddress, uint256 maxTokensPerLiquidityPool, bool hasUniqueLiquidityPools) {
        return (_ethereumAddress, _maxTokensPerLiquidityPool, _hasUniqueLiquidityPools);
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
                    liquidityPoolCreationParams.minAmounts,
                    liquidityPoolCreationParams.receiver,
                    liquidityPoolCreationParams.deadline
                ));
                return (liquidityPoolAmount, liquidityPoolTokenAmounts, liquidityPoolId, liquidityPoolTokens);
            }
        }
        address liquidityPoolCreator = _getLiquidityPoolCreator(liquidityPoolCreationParams.tokenAddresses, liquidityPoolCreationParams.amounts, liquidityPoolCreationParams.involvingETH, liquidityPoolCreationParams.additionalData);
        _transferToMeAndApprove(liquidityPoolCreationParams.tokenAddresses, liquidityPoolCreationParams.amounts, liquidityPoolCreator, liquidityPoolCreationParams.involvingETH);
        (liquidityPoolAmount, liquidityPoolTokenAmounts, liquidityPoolId, liquidityPoolTokens) = _createLiquidityPoolAndAddLiquidity(liquidityPoolCreationParams);
        _checkMinAmounts(liquidityPoolTokenAmounts, liquidityPoolCreationParams.minAmounts);
        require(block.timestamp < liquidityPoolCreationParams.deadline, "too late");
        emit NewLiquidityPool(liquidityPoolId);
    }

    function addLiquidityEnsuringPoolBatch(LiquidityPoolCreationParams[] calldata liquidityPoolCreationParams) external payable returns(uint256[] memory liquidityPoolAmounts, uint256[][] memory liquidityPoolTokenAmounts, uint256[] memory liquidityPoolIds, address[][] memory liquidityPoolTokens) {
        liquidityPoolAmounts = new uint256[](liquidityPoolCreationParams.length);
        liquidityPoolTokenAmounts = new uint256[][](liquidityPoolCreationParams.length);
        liquidityPoolIds = new uint256[](liquidityPoolCreationParams.length);
        liquidityPoolTokens = new address[][](liquidityPoolCreationParams.length);
        for(uint256 i = 0; i < liquidityPoolCreationParams.length; i++) {
            LiquidityPoolCreationParams memory liquidityPoolCreationParamsElement = liquidityPoolCreationParams[i];
            (liquidityPoolAmounts[i], liquidityPoolTokenAmounts[i], liquidityPoolIds[i], liquidityPoolTokens[i]) = addLiquidityEnsuringPool(liquidityPoolCreationParamsElement);
        }
    }

    function addLiquidity(LiquidityPoolParams memory liquidityPoolParams) public override virtual payable returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, uint256 liquidityPoolId, address[] memory liquidityPoolTokens) {
        ProcessedLiquidityPoolParams memory processedLiquidityPoolParams = _processLiquidityPoolParams(liquidityPoolParams);
        _transferToMeAndApprove(liquidityPoolTokens = processedLiquidityPoolParams.liquidityPoolTokens, processedLiquidityPoolParams.tokensAmounts, processedLiquidityPoolParams.liquidityPoolOperator, liquidityPoolParams.involvingETH);
        (liquidityPoolAmount, liquidityPoolTokenAmounts, liquidityPoolId) = _addLiquidity(processedLiquidityPoolParams);
        _checkMinAmounts(liquidityPoolTokenAmounts, processedLiquidityPoolParams.minAmounts);
        require(block.timestamp < processedLiquidityPoolParams.deadline, "too late");
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
                _collectOrApprove(liquidityPoolTokens[i][z], processedLiquidityPoolDataArray[i].tokensAmounts[z], processedLiquidityPoolDataArray[i].liquidityPoolOperator, processedLiquidityPoolDataArray[i].involvingETH);
            }
        }
        _transferToMeApproveAndCleanInternalStorage();
        for(uint256 i = 0; i < processedLiquidityPoolDataArray.length; i++) {
            (liquidityPoolAmounts[i], liquidityPoolTokenAmounts[i], liquidityPoolIds[i]) = _addLiquidity(processedLiquidityPoolDataArray[i]);
            _checkMinAmounts(liquidityPoolTokenAmounts[i], processedLiquidityPoolDataArray[i].minAmounts);
            require(block.timestamp < processedLiquidityPoolDataArray[i].deadline, "too late");
        }
    }

    function removeLiquidity(LiquidityPoolParams memory liquidityPoolParams) public override virtual returns(uint256 removedLiquidityPoolAmount, uint256[] memory removedLiquidityPoolTokenAmounts, address[] memory liquidityPoolTokens) {
        ProcessedLiquidityPoolParams memory processedLiquidityPoolParams = _processLiquidityPoolParams(liquidityPoolParams);
        liquidityPoolTokens = processedLiquidityPoolParams.liquidityPoolTokens;
        address liquidityPoolAddress = _toAddress(processedLiquidityPoolParams.liquidityPoolId);
        _transferToMeAndApprove(liquidityPoolAddress.asSingleElementArray(), processedLiquidityPoolParams.liquidityPoolAmount.asSingleElementArray(), processedLiquidityPoolParams.liquidityPoolOperator, false);
        (removedLiquidityPoolAmount, removedLiquidityPoolTokenAmounts) = _removeLiquidity(processedLiquidityPoolParams);
        _checkMinAmounts(removedLiquidityPoolTokenAmounts, processedLiquidityPoolParams.minAmounts);
        require(block.timestamp < processedLiquidityPoolParams.deadline, "too late");
    }

    function removeLiquidityBatch(LiquidityPoolParams[] memory liquidityPoolParams) public override virtual returns(uint256[] memory removedLiquidityPoolAmounts, uint256[][] memory removedLiquidityPoolTokenAmounts, address[][] memory liquidityPoolTokens) {
        removedLiquidityPoolAmounts = new uint256[](liquidityPoolParams.length);
        removedLiquidityPoolTokenAmounts = new uint256[][](liquidityPoolParams.length);
        liquidityPoolTokens = new address[][](liquidityPoolParams.length);
        ProcessedLiquidityPoolParams[] memory processedLiquidityPoolDataArray = new ProcessedLiquidityPoolParams[](liquidityPoolParams.length);
        for(uint256 i = 0; i < liquidityPoolParams.length; i++) {
            processedLiquidityPoolDataArray[i] = _processLiquidityPoolParams(liquidityPoolParams[i]);
            liquidityPoolTokens[i] = processedLiquidityPoolDataArray[i].liquidityPoolTokens;
            _collectOrApprove(_toAddress(processedLiquidityPoolDataArray[i].liquidityPoolId), processedLiquidityPoolDataArray[i].liquidityPoolAmount, processedLiquidityPoolDataArray[i].liquidityPoolOperator, false);
        }
        _transferToMeApproveAndCleanInternalStorage();
        for(uint256 i = 0; i < processedLiquidityPoolDataArray.length; i++) {
            (removedLiquidityPoolAmounts[i], removedLiquidityPoolTokenAmounts[i]) = _removeLiquidity(processedLiquidityPoolDataArray[i]);
            _checkMinAmounts(removedLiquidityPoolTokenAmounts[i], processedLiquidityPoolDataArray[i].minAmounts);
            require(block.timestamp < processedLiquidityPoolDataArray[i].deadline, "too late");
        }
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
        require(block.timestamp < swapParams.deadline, "too late");
    }

    function swapBatch(SwapParams[] memory swapParams) public override virtual payable returns(uint256[] memory receivedValues) {
        ProcessedSwapParams[] memory processedSwapDatas = new ProcessedSwapParams[](swapParams.length);
        receivedValues = new uint256[](swapParams.length);
        for(uint256 i = 0; i < swapParams.length; i++) {
            processedSwapDatas[i] = _processSwapParams(swapParams[i]);
            _collectOrApprove(processedSwapDatas[i].inputToken, processedSwapDatas[i].amount, processedSwapDatas[i].liquidityPoolOperator, processedSwapDatas[i].enterInETH);
        }
        _transferToMeApproveAndCleanInternalStorage();
        for(uint256 i = 0; i < swapParams.length; i++) {
            receivedValues[i] = _swap(processedSwapDatas[i]);
            _checkMinAmount(receivedValues[i], processedSwapDatas[i].minAmount);
        }
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

    function _getLiquidityPoolOperator(uint256 liquidityPoolId, address[] memory liquidityPoolTokens, bytes memory additionalData) internal virtual view returns(address);

    function _getSwapOperator(uint256 liquidityPoolId, address[] memory liquidityPoolTokens, bytes memory additionalData) internal virtual view returns(address);

    function _addLiquidity(ProcessedLiquidityPoolParams memory processedLiquidityPoolParams) internal virtual returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokens, uint256 liquidityPoolId);

    function _removeLiquidity(ProcessedLiquidityPoolParams memory processedLiquidityPoolParams) internal virtual returns(uint256, uint256[] memory);

    function _swap(ProcessedSwapParams memory processedSwapParams) internal virtual returns(uint256 outputAmount);

    function _getLiquidityPoolCreator(address[] memory tokenAddresses, uint256[] memory amounts, bool involvingETH, bytes memory additionalData) internal virtual view returns(address);

    function _createLiquidityPoolAndAddLiquidity(LiquidityPoolCreationParams memory liquidityPoolCreationParams) internal virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId, address[] memory orderedTokens);

    function _getSwapOutput(uint256 amount, uint256[] memory liquidityPoolIds, address[] memory path) view internal virtual returns(uint256);
    function _getSwapInput(uint256 amount, uint256[] memory liquidityPoolIds, address[] memory path) view internal virtual returns(uint256);

    function _checkAddLiquidityAdditionalData(ProcessedLiquidityPoolParams[] memory processedLiquidityPoolParams) internal virtual view;
    function _checkRemoveLiquidityAdditionalData(ProcessedLiquidityPoolParams[] memory processedLiquidityPoolParams) internal virtual view;
    function _checkSwapAdditionalData(ProcessedSwapParams[] memory processedSwapParams) internal virtual view;

    function _delegateMode() internal view returns(bool) {
        return _this != address(this);
    }

    function _processLiquidityPoolParams(LiquidityPoolParams memory liquidityPoolParams) internal view returns(ProcessedLiquidityPoolParams memory) {
        require(liquidityPoolParams.amount > 0, "Zero amount");
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
            liquidityPoolParams.minAmounts,
            liquidityPoolParams.receiver == address(0) ? msg.sender : liquidityPoolParams.receiver,
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
        require(swapParams.amount > 0, "Zero amount");
        require(swapParams.path.length > 0 && swapParams.liquidityPoolIds.length == swapParams.path.length, "Invalid length");
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
            swapParams.receiver == address(0) ? msg.sender : swapParams.receiver,
            swapParams.deadline,
            _getSwapOperator(swapParams.liquidityPoolIds[0], liquidityPoolTokens, swapParams.additionalData)
        );
    }

    function _processSwapParams(SwapParams[] memory swapParams) internal view returns(ProcessedSwapParams[] memory processedSwapParams) {
        processedSwapParams = new ProcessedSwapParams[](swapParams.length);
        for(uint256 i = 0; i < processedSwapParams.length; i++) {
            processedSwapParams[i] = _processSwapParams(swapParams[i]);
        }
    }

    function _transferToMeAndApprove(address[] memory tokens, uint256[] memory amounts, address operator, bool involvingETH) internal {
        require(tokens.length == amounts.length, "tokens");
        bool delegateMode = _delegateMode();
        for(uint256 i = 0; i < tokens.length; i++) {
            address tokenAddress = involvingETH && tokens[i] == _ethereumAddress ? address(0) : tokens[i];
            uint256 amount = amounts[i];
            tokenAddress.safeApprove(operator, amount);
            if(delegateMode) {
                continue;
            }
            if(tokenAddress == address(0)) {
                require(msg.value == amount, "Incorrect eth amount");
                return;
            }
            tokenAddress.safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function _collectOrApprove(address tokenAddress, uint256 amount, address operator, bool involvingETH) private {
        require(amount != 0, "amount");
        address realTokenAddress = involvingETH && tokenAddress == _ethereumAddress ? address(0) : tokenAddress;
        if(_delegateMode()) {
            return realTokenAddress.safeApprove(operator, realTokenAddress.allowance(address(this), operator) + amount);
        }
        _internalStorage.operator = operator;
        uint256 oldAmount = _internalStorage.amount[realTokenAddress];
        if(oldAmount == 0) {
            _internalStorage.tokens.push(realTokenAddress);
        }
        _internalStorage.amount[realTokenAddress] = oldAmount + amount;
    }

    function _transferToMeApproveAndCleanInternalStorage() private {
        if(_delegateMode()) {
            return;
        }
        address[] memory tokens = _internalStorage.tokens;
        uint256[] memory amounts = new uint256[](tokens.length);
        for(uint256 i = 0; i < tokens.length; i++) {
            amounts[i] = _internalStorage.amount[tokens[i]];
        }
        _transferToMeAndApprove(tokens, amounts, _internalStorage.operator, false);
        delete _internalStorage;
    }

    function _checkMinAmounts(uint256[] memory amounts, uint256[] memory minAmounts) internal pure {
        for(uint256 i = 0; i < amounts.length; i++) {
            _checkMinAmount(amounts[i], minAmounts[i]);
        }
    }

    function _checkMinAmount(uint256 amount, uint256 minAmount) internal pure {
        require(amount >= minAmount, "too little received");
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