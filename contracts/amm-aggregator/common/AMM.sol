//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./IAMM.sol";
import "../util/IERC20.sol";

abstract contract AMM is IAMM {

    struct ProcessedLiquidityPoolData {
        address liquidityPoolAddress;
        uint256 liquidityPoolAmount;
        address[] liquidityPoolTokens;
        uint256[] tokensAmounts;
        bool ethIsInvolved;
        address liquidityPoolOperator;
        address receiver;
    }

    struct ProcessedSwapData {
        bool enterInETH;
        bool exitInETH;
        address[] liquidityPoolAddresses;
        address[] paths;
        address liquidityPoolOperator;
        address inputToken;
        uint256 amount;
        address receiver;
    }

    mapping(address => uint256) internal _tokenIndex;
    address[] internal _tokensToTransfer;
    address[] internal _operators;
    uint256[] internal _tokenAmounts;
    uint256 private _tokensLength = 1;

    address public override ethereumAddress;

    constructor(address _ethereumAddress) {
        ethereumAddress = _ethereumAddress;
    }

    receive() external virtual payable {
    }

    function byPercentage(address liquidityPoolAddress, uint256 numerator, uint256 denominator) public override view returns (uint256 liquidityPoolAmount, uint256[] memory tokenAmounts, address[] memory liquidityPoolTokens) {
        (liquidityPoolAmount, tokenAmounts, liquidityPoolTokens) = this.byLiquidityPool(liquidityPoolAddress);

        liquidityPoolAmount = (liquidityPoolAmount * numerator) / denominator;

        for(uint256 i = 0; i < tokenAmounts.length; i++) {
            tokenAmounts[i] = (tokenAmounts[i] * numerator) / denominator;
        }
    }

    function byLiquidityPoolAmount(address liquidityPoolAddress, uint256 liquidityPoolAmount) public virtual override view returns(uint256[] memory tokenAmounts, address[] memory liquidityPoolTokens) {

        uint256 numerator = liquidityPoolAmount;
        uint256 denominator;

        (denominator, tokenAmounts, liquidityPoolTokens) = this.byLiquidityPool(liquidityPoolAddress);

        for(uint256 i = 0; i < tokenAmounts.length; i++) {
            tokenAmounts[i] = (tokenAmounts[i] * numerator) / denominator;
        }
    }

    function byTokenAmount(address liquidityPoolAddress, uint256 tokenIndex, uint256 tokenAmount) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokenAmounts, address[] memory liquidityPoolTokens) {

        (liquidityPoolAmount, tokenAmounts, liquidityPoolTokens) = this.byLiquidityPool(liquidityPoolAddress);

        uint256 numerator = tokenAmount;
        uint256 denominator = tokenAmounts[tokenIndex];

        liquidityPoolAmount = (liquidityPoolAmount * numerator) / denominator;

        for(uint256 i = 0; i < tokenAmounts.length; i++) {
            if(i == tokenIndex) {
                tokenAmounts[i] = numerator;
                continue;
            }
            tokenAmounts[i] = (tokenAmounts[i] * numerator) / denominator;
        }
    }

    function addLiquidity(LiquidityPoolData calldata data) public override virtual payable returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory liquidityPoolTokens) {
        ProcessedLiquidityPoolData memory processedLiquidityPoolData = _processLiquidityPoolData(data);
        _transferToMeAndCheckAllowance(liquidityPoolTokens = processedLiquidityPoolData.liquidityPoolTokens, processedLiquidityPoolData.tokensAmounts, processedLiquidityPoolData.liquidityPoolOperator, data.ethIsInvolved);
        (liquidityPoolAmount, tokensAmounts) = _addLiquidity(processedLiquidityPoolData);
        _flushBack(liquidityPoolTokens, processedLiquidityPoolData.tokensAmounts, tokensAmounts);
    }

    function addLiquidityBatch(LiquidityPoolData[] calldata data) public override virtual payable returns(uint256[] memory liquidityPoolAmounts, uint256[][] memory tokensAmounts, address[][] memory liquidityPoolTokens) {
        liquidityPoolAmounts = new uint256[](data.length);
        tokensAmounts = new uint256[][](data.length);
        liquidityPoolTokens = new address[][](data.length);
        ProcessedLiquidityPoolData[] memory processedLiquidityPoolDataArray = new ProcessedLiquidityPoolData[](data.length);
        for(uint256 i = 0; i < data.length; i++) {
            processedLiquidityPoolDataArray[i] = _processLiquidityPoolData(data[i]);
            _collect(liquidityPoolTokens[i] = processedLiquidityPoolDataArray[i].liquidityPoolTokens, processedLiquidityPoolDataArray[i].tokensAmounts, processedLiquidityPoolDataArray[i].liquidityPoolOperator, processedLiquidityPoolDataArray[i].ethIsInvolved);
        }
        _transferToMeAndCheckAllowance();
        uint256[] memory collected = new uint256[](_tokensLength);
        for(uint256 i = 0; i < processedLiquidityPoolDataArray.length; i++) {
            (liquidityPoolAmounts[i], tokensAmounts[i]) = _addLiquidity(processedLiquidityPoolDataArray[i]);
            for(uint256 z = 0; z < tokensAmounts[i].length; z++) {
                collected[_tokenIndex[liquidityPoolTokens[i][z]]] += tokensAmounts[i][z];
            }
        }
        _flushBackAndClear(collected);
    }

    function removeLiquidity(LiquidityPoolData calldata data) public override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory liquidityPoolTokens) {
        ProcessedLiquidityPoolData memory processedLiquidityPoolData = _processLiquidityPoolData(data);
        liquidityPoolTokens = processedLiquidityPoolData.liquidityPoolTokens;
        _transferToMeAndCheckAllowance(processedLiquidityPoolData.liquidityPoolAddress, processedLiquidityPoolData.liquidityPoolAmount, processedLiquidityPoolData.liquidityPoolOperator);
        (liquidityPoolAmount, tokensAmounts) = _removeLiquidity(processedLiquidityPoolData);
        _flushBack(processedLiquidityPoolData.liquidityPoolAddress, processedLiquidityPoolData.liquidityPoolAmount, liquidityPoolAmount);
    }

    function removeLiquidityBatch(LiquidityPoolData[] calldata data) public override virtual returns(uint256[] memory liquidityPoolAmounts, uint256[][] memory tokensAmounts, address[][] memory liquidityPoolTokens) {
        liquidityPoolAmounts = new uint256[](data.length);
        tokensAmounts = new uint256[][](data.length);
        liquidityPoolTokens = new address[][](data.length);
        ProcessedLiquidityPoolData[] memory processedLiquidityPoolDataArray = new ProcessedLiquidityPoolData[](data.length);
        for(uint256 i = 0; i < data.length; i++) {
            processedLiquidityPoolDataArray[i] = _processLiquidityPoolData(data[i]);
            liquidityPoolTokens[i] = processedLiquidityPoolDataArray[i].liquidityPoolTokens;
            _collect(processedLiquidityPoolDataArray[i].liquidityPoolAddress, processedLiquidityPoolDataArray[i].liquidityPoolAmount, processedLiquidityPoolDataArray[i].liquidityPoolOperator, false);
        }
        _transferToMeAndCheckAllowance();
        uint256[] memory collected = new uint256[](_tokensLength);
        for(uint256 i = 0; i < processedLiquidityPoolDataArray.length; i++) {
            (liquidityPoolAmounts[i], tokensAmounts[i]) = _removeLiquidity(processedLiquidityPoolDataArray[i]);
            collected[_tokenIndex[processedLiquidityPoolDataArray[i].liquidityPoolAddress]] += liquidityPoolAmounts[i];
        }
        _flushBackAndClear(collected);
    }

    function swapLiquidity(SwapData calldata data) public override payable returns(uint256 outputAmount) {
        ProcessedSwapData memory processedSwapData = _processSwapData(data);
        _transferToMeAndCheckAllowance(processedSwapData.inputToken, processedSwapData.amount, processedSwapData.liquidityPoolOperator);
        outputAmount = _swapLiquidity(processedSwapData);
        _flushBack(processedSwapData.enterInETH ? address(0) : processedSwapData.inputToken , processedSwapData.amount, 0);
    }

    function swapLiquidityBatch(SwapData[] calldata data) public override payable returns(uint256[] memory outputAmounts) {
        ProcessedSwapData[] memory processedSwapDatas = new ProcessedSwapData[](data.length);
        outputAmounts = new uint256[](data.length);
        for(uint256 i = 0; i < data.length; i++) {
            processedSwapDatas[i] = _processSwapData(data[i]);
            _collect(processedSwapDatas[i].inputToken, processedSwapDatas[i].amount, processedSwapDatas[i].liquidityPoolOperator, processedSwapDatas[i].enterInETH);
        }
        _transferToMeAndCheckAllowance();
        for(uint256 i = 0; i < data.length; i++) {
            outputAmounts[i] = _swapLiquidity(processedSwapDatas[i]);
        }
        _flushBackAndClear(new uint256[](0));
    }

    function _getLiquidityPoolOperator(address liquidityPoolAddress, address[] memory liquidityPoolTokens) internal virtual view returns(address);

    function _addLiquidity(ProcessedLiquidityPoolData memory processedLiquidityPoolData) internal virtual returns(uint256, uint256[] memory);

    function _removeLiquidity(ProcessedLiquidityPoolData memory processedLiquidityPoolData) internal virtual returns(uint256, uint256[] memory);

    function _swapLiquidity(ProcessedSwapData memory data) internal virtual returns(uint256 outputAmount);

    function _processLiquidityPoolData(LiquidityPoolData calldata data) private view returns(ProcessedLiquidityPoolData memory) {
        require(data.amount > 0, "Zero amount");
        uint256[] memory tokensAmounts;
        address[] memory liquidityPoolTokens;
        uint256 liquidityPoolAmount;
        if(data.amountIsLiquidityPool) {
            (tokensAmounts, liquidityPoolTokens) = this.byLiquidityPoolAmount(data.liquidityPoolAddress, liquidityPoolAmount = data.amount);
        } else {
            (liquidityPoolAmount, tokensAmounts, liquidityPoolTokens) = this.byTokenAmount(data.liquidityPoolAddress, data.tokenIndex, data.amount);
        }
        bool ethIsInvolved = data.ethIsInvolved;
        for(uint256 i = 0; i < liquidityPoolTokens.length; i++) {
            if(liquidityPoolTokens[i] == address(0)) {
                ethIsInvolved = true;
            }
        }
        return ProcessedLiquidityPoolData(
            data.liquidityPoolAddress,
            liquidityPoolAmount,
            liquidityPoolTokens,
            tokensAmounts,
            ethIsInvolved,
            _getLiquidityPoolOperator(data.liquidityPoolAddress, liquidityPoolTokens),
            data.receiver == address(0) ? msg.sender : data.receiver
        );
    }

    function _processSwapData(SwapData calldata data) private view returns(ProcessedSwapData memory) {
        require(data.amount > 0, "Zero amount");
        require(data.paths.length > 0 && data.liquidityPoolAddresses.length == data.paths.length, "Invalid length");
        ( , ,address[] memory liquidityPoolTokens) = this.byLiquidityPool(data.liquidityPoolAddresses[0]);
        return ProcessedSwapData(
            data.enterInETH && data.inputToken == ethereumAddress,
            data.exitInETH && data.paths[data.paths.length - 1] == ethereumAddress,
            data.liquidityPoolAddresses,
            data.paths,
            _getLiquidityPoolOperator(data.liquidityPoolAddresses[0], liquidityPoolTokens),
            data.inputToken,
            data.amount,
            data.receiver == address(0) ? msg.sender : data.receiver
        );
    }

    function _collect(address[] memory tokenAddresses, uint256[] memory tokenAmounts, address operator, bool ethIsInvolved) private {
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            _collect(tokenAddresses[i], tokenAmounts[i], operator, ethIsInvolved);
        }
    }

    function _collect(address tokenAddress, uint256 tokenAmount, address operator, bool ethIsInvolved) private {
        address realTokenAddress = ethIsInvolved && tokenAddress == ethereumAddress ? address(0) : tokenAddress;
        uint256 position = _tokenIndex[realTokenAddress];
        if(position == 0) {
            _tokenIndex[realTokenAddress] = position = (_tokensLength++) - 1;
            _tokensToTransfer.push(realTokenAddress);
            _operators.push(operator);
            _tokenAmounts.push(0);
        }
        _tokenAmounts[position] = _tokenAmounts[position] + tokenAmount;
    }

    function _transferToMeAndCheckAllowance(address[] memory tokens, uint256[] memory amounts, address operator, bool ethIsInvolved) private {
        for(uint256 i = 0; i < tokens.length; i++) {
            _transferToMeAndCheckAllowance(ethIsInvolved && tokens[i] == ethereumAddress ? address(0) : tokens[i] , amounts[i], operator);
        }
    }

    function _transferToMeAndCheckAllowance() private {
        for(uint256 i = 0; i < _tokensLength; i++) {
            _transferToMeAndCheckAllowance(_tokensToTransfer[i], _tokenAmounts[i], _operators[i]);
        }
    }

    function _flushBackAndClear(uint256[] memory collectedAmounts) private {
        for(uint256 i = 0; i < _tokensLength; i++) {
            delete _tokenIndex[_tokensToTransfer[i]];
            _flushBack(_tokensToTransfer[i], _tokenAmounts[i], collectedAmounts.length > 0 ? collectedAmounts[i] : 0);
        }
        _tokensLength = 1;
        delete _tokensToTransfer;
        delete _operators;
        delete _tokenAmounts;
    }

    function _transferToMeAndCheckAllowance(address tokenAddress, uint256 value, address operator) private {
        _transferToMe(tokenAddress, value);
        _checkAllowance(tokenAddress, value, operator);
    }

    function _transferToMe(address tokenAddress, uint256 value) private {
        if(tokenAddress == address(0)) {
            require(msg.value == value, "Incorrect eth value");
        }
        _safeTransferFrom(tokenAddress, msg.sender, address(this), value);
    }

    function _flushBack(address[] memory tokenAddresses, uint256[] memory originalAmounts, uint256[] memory collectedAmounts) private {
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            _flushBack(tokenAddresses[i], originalAmounts[i], collectedAmounts.length > 0 ? collectedAmounts[i] : 0);
        }
    }

    function _flushBack(address tokenAddress, uint256 originalAmount, uint256 collectedAmount) private {
        uint256 amount = originalAmount != 0 && collectedAmount != 0 ? originalAmount - collectedAmount : tokenAddress == address(0) ? address(this).balance : IERC20(tokenAddress).balanceOf(address(this));
        if(amount == 0) {
            return;
        }
        if(tokenAddress == address(0)) {
            payable(msg.sender).transfer(amount);
            return;
        }
        _safeTransfer(tokenAddress, msg.sender, amount);
    }

    function _checkAllowance(address tokenAddress, uint256 value, address operator) private {
        if(tokenAddress == address(0) || operator == address(0)) {
            return;
        }
        IERC20 token = IERC20(tokenAddress);
        if(token.allowance(address(this), operator) <= value) {
            _safeApprove(tokenAddress, operator, token.totalSupply());
        }
    }

    function _safeApprove(address erc20TokenAddress, address to, uint256 value) private {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).approve.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'APPROVE_FAILED');
    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) private {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }

    function _safeTransferFrom(address erc20TokenAddress, address from, address to, uint256 value) private {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFERFROM_FAILED');
    }
}