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
        bool involvingETH;
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

    mapping(address => uint256) private _tokenIndex;
    address[] private _tokensToTransfer;
    address[] private _operators;
    uint256[] private _tokenAmounts;

    string internal _name;
    uint256 internal immutable _version;
    address internal immutable _ethereumAddress;
    uint256 internal immutable _maxTokensPerLiquidityPool;
    bool internal immutable _hasUniqueLiquidityPools;

    constructor(string memory name, uint256 version, address ethereumAddress, uint256 maxTokensPerLiquidityPool, bool hasUniqueLiquidityPools) {
        _name = name;
        _version = version;
        _ethereumAddress = ethereumAddress;
        _maxTokensPerLiquidityPool = maxTokensPerLiquidityPool;
        _hasUniqueLiquidityPools = hasUniqueLiquidityPools;
    }

    receive() external virtual payable {
    }

    function info() view public virtual override returns(string memory, uint256) {
        return (_name, _version);
    }

    function data() view public virtual override returns(address, uint256, bool) {
        return (_ethereumAddress, _maxTokensPerLiquidityPool, _hasUniqueLiquidityPools);
    }

    function balanceOf(address liquidityPoolAddress, address owner) view public virtual override returns (uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory liquidityPoolTokens) {
        (tokensAmounts, liquidityPoolTokens) = byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount = IERC20(liquidityPoolAddress).balanceOf(owner));
    }

    function byPercentage(address liquidityPoolAddress, uint256 numerator, uint256 denominator) view public virtual override returns (uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory liquidityPoolTokens) {
        (liquidityPoolAmount, tokensAmounts, liquidityPoolTokens) = this.byLiquidityPool(liquidityPoolAddress);

        liquidityPoolAmount = (liquidityPoolAmount * numerator) / denominator;

        for(uint256 i = 0; i < tokensAmounts.length; i++) {
            tokensAmounts[i] = (tokensAmounts[i] * numerator) / denominator;
        }
    }

    function byLiquidityPoolAmount(address liquidityPoolAddress, uint256 liquidityPoolAmount) view public virtual override returns(uint256[] memory tokensAmounts, address[] memory liquidityPoolTokens) {

        uint256 numerator = liquidityPoolAmount;
        uint256 denominator;

        (denominator, tokensAmounts, liquidityPoolTokens) = this.byLiquidityPool(liquidityPoolAddress);

        for(uint256 i = 0; i < tokensAmounts.length; i++) {
            tokensAmounts[i] = (tokensAmounts[i] * numerator) / denominator;
        }
    }

    function byTokenAmount(address liquidityPoolAddress, address tokenAddress, uint256 tokenAmount) view public virtual override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory liquidityPoolTokens) {

        (liquidityPoolAmount, tokensAmounts, liquidityPoolTokens) = this.byLiquidityPool(liquidityPoolAddress);

        uint256 numerator = tokenAmount;
        uint256 denominator;

        for(uint256 i = 0; i < liquidityPoolTokens.length; i++) {
            if(liquidityPoolTokens[i] == tokenAddress) {
                denominator =  tokensAmounts[i];
                break;
            }
        }

        liquidityPoolAmount = (liquidityPoolAmount * numerator) / denominator;

        for(uint256 i = 0; i < tokensAmounts.length; i++) {
            if(liquidityPoolTokens[i] == tokenAddress) {
                tokensAmounts[i] = numerator;
                continue;
            }
            tokensAmounts[i] = (tokensAmounts[i] * numerator) / denominator;
        }
    }

    function createLiquidityPoolAndAddLiquidity(address[] memory tokenAddresses, uint256[] memory amounts, bool involvingETH, address receiver) payable public virtual override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address liquidityPoolAddress, address[] memory orderedTokens) {
        require(tokenAddresses.length > 1 && tokenAddresses.length == amounts.length && (_maxTokensPerLiquidityPool == 0 || tokenAddresses.length == _maxTokensPerLiquidityPool), "Invalid length");
        if(_hasUniqueLiquidityPools) {
            (liquidityPoolAmount, tokensAmounts, liquidityPoolAddress, orderedTokens) = this.byTokens(tokenAddresses);
            if(liquidityPoolAddress != address(0)) {
                (liquidityPoolAmount, tokensAmounts, orderedTokens) = addLiquidity(LiquidityPoolData(
                    liquidityPoolAddress,
                    amounts[0],
                    tokenAddresses[0],
                    false,
                    involvingETH,
                    receiver
                ));
                return (liquidityPoolAmount, tokensAmounts, liquidityPoolAddress, orderedTokens);
            }
        }
        address liquidityPoolCreator = _getLiquidityPoolCreator(tokenAddresses, amounts, involvingETH);
        _transferToMeAndCheckAllowance(tokenAddresses, amounts, liquidityPoolCreator, involvingETH);
        return _createLiquidityPoolAndAddLiquidity(tokenAddresses, amounts, involvingETH, liquidityPoolCreator, receiver);
    }

    function addLiquidity(LiquidityPoolData memory data) payable public virtual override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory liquidityPoolTokens) {
        ProcessedLiquidityPoolData memory processedLiquidityPoolData = _processLiquidityPoolData(data);
        _transferToMeAndCheckAllowance(liquidityPoolTokens = processedLiquidityPoolData.liquidityPoolTokens, processedLiquidityPoolData.tokensAmounts, processedLiquidityPoolData.liquidityPoolOperator, data.involvingETH);
        (liquidityPoolAmount, tokensAmounts) = _addLiquidity(processedLiquidityPoolData);
        _flushBack(liquidityPoolTokens, processedLiquidityPoolData.tokensAmounts, tokensAmounts);
    }

    function addLiquidityBatch(LiquidityPoolData[] memory data) payable public virtual override returns(uint256[] memory liquidityPoolAmounts, uint256[][] memory tokensAmounts, address[][] memory liquidityPoolTokens) {
        liquidityPoolAmounts = new uint256[](data.length);
        tokensAmounts = new uint256[][](data.length);
        liquidityPoolTokens = new address[][](data.length);
        ProcessedLiquidityPoolData[] memory processedLiquidityPoolDataArray = new ProcessedLiquidityPoolData[](data.length);
        for(uint256 i = 0; i < data.length; i++) {
            processedLiquidityPoolDataArray[i] = _processLiquidityPoolData(data[i]);
            _collect(liquidityPoolTokens[i] = processedLiquidityPoolDataArray[i].liquidityPoolTokens, processedLiquidityPoolDataArray[i].tokensAmounts, processedLiquidityPoolDataArray[i].liquidityPoolOperator, processedLiquidityPoolDataArray[i].involvingETH);
        }
        _transferToMeAndCheckAllowance();
        uint256[] memory collected = new uint256[](_tokensToTransfer.length);
        for(uint256 i = 0; i < processedLiquidityPoolDataArray.length; i++) {
            (liquidityPoolAmounts[i], tokensAmounts[i]) = _addLiquidity(processedLiquidityPoolDataArray[i]);
            for(uint256 z = 0; z < tokensAmounts[i].length; z++) {
                collected[_tokenIndex[liquidityPoolTokens[i][z]]] += tokensAmounts[i][z];
            }
        }
        _flushBackAndClear(collected);
    }

    function removeLiquidity(LiquidityPoolData memory data) public virtual override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory liquidityPoolTokens) {
        ProcessedLiquidityPoolData memory processedLiquidityPoolData = _processLiquidityPoolData(data);
        liquidityPoolTokens = processedLiquidityPoolData.liquidityPoolTokens;
        _transferToMeAndCheckAllowance(processedLiquidityPoolData.liquidityPoolAddress, processedLiquidityPoolData.liquidityPoolAmount, processedLiquidityPoolData.liquidityPoolOperator);
        (liquidityPoolAmount, tokensAmounts) = _removeLiquidity(processedLiquidityPoolData);
        _flushBack(processedLiquidityPoolData.liquidityPoolAddress, processedLiquidityPoolData.liquidityPoolAmount, liquidityPoolAmount);
    }

    function removeLiquidityBatch(LiquidityPoolData[] memory data) public virtual override returns(uint256[] memory liquidityPoolAmounts, uint256[][] memory tokensAmounts, address[][] memory liquidityPoolTokens) {
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
        uint256[] memory collected = new uint256[](_tokensToTransfer.length);
        for(uint256 i = 0; i < processedLiquidityPoolDataArray.length; i++) {
            (liquidityPoolAmounts[i], tokensAmounts[i]) = _removeLiquidity(processedLiquidityPoolDataArray[i]);
            collected[_tokenIndex[processedLiquidityPoolDataArray[i].liquidityPoolAddress]] += liquidityPoolAmounts[i];
        }
        _flushBackAndClear(collected);
    }

    function swapLiquidity(SwapData memory data) payable public virtual override returns(uint256 outputAmount) {
        ProcessedSwapData memory processedSwapData = _processSwapData(data);
        _transferToMeAndCheckAllowance(processedSwapData.inputToken, processedSwapData.amount, processedSwapData.liquidityPoolOperator);
        outputAmount = _swapLiquidity(processedSwapData);
        _flushBack(processedSwapData.enterInETH ? address(0) : processedSwapData.inputToken , processedSwapData.amount, 0);
    }

    function swapLiquidityBatch(SwapData[] memory data) payable public virtual override returns(uint256[] memory outputAmounts) {
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

    function _getLiquidityPoolCreator(address[] memory tokenAddresses, uint256[] memory amounts, bool involvingETH) internal virtual view returns(address);

    function _createLiquidityPoolAndAddLiquidity(address[] memory tokenAddresses, uint256[] memory amounts, bool involvingETH, address operator, address receiver) internal virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address liquidityPoolAddress, address[] memory orderedTokens);

    function _processLiquidityPoolData(LiquidityPoolData memory data) private view returns(ProcessedLiquidityPoolData memory) {
        require(data.amount > 0, "Zero amount");
        uint256[] memory tokensAmounts;
        address[] memory liquidityPoolTokens;
        uint256 liquidityPoolAmount;
        if(data.amountIsLiquidityPool) {
            (tokensAmounts, liquidityPoolTokens) = this.byLiquidityPoolAmount(data.liquidityPoolAddress, liquidityPoolAmount = data.amount);
        } else {
            (liquidityPoolAmount, tokensAmounts, liquidityPoolTokens) = this.byTokenAmount(data.liquidityPoolAddress, data.tokenAddress, data.amount);
        }
        bool involvingETH = data.involvingETH;
        for(uint256 i = 0; i < liquidityPoolTokens.length; i++) {
            if(liquidityPoolTokens[i] == address(0)) {
                involvingETH = true;
            }
        }
        return ProcessedLiquidityPoolData(
            data.liquidityPoolAddress,
            liquidityPoolAmount,
            liquidityPoolTokens,
            tokensAmounts,
            involvingETH,
            _getLiquidityPoolOperator(data.liquidityPoolAddress, liquidityPoolTokens),
            data.receiver == address(0) ? msg.sender : data.receiver
        );
    }

    function _processSwapData(SwapData memory data) private view returns(ProcessedSwapData memory) {
        require(data.amount > 0, "Zero amount");
        require(data.paths.length > 0 && data.liquidityPoolAddresses.length == data.paths.length, "Invalid length");
        ( , ,address[] memory liquidityPoolTokens) = this.byLiquidityPool(data.liquidityPoolAddresses[0]);
        return ProcessedSwapData(
            data.enterInETH && data.inputToken == _ethereumAddress,
            data.exitInETH && data.paths[data.paths.length - 1] == _ethereumAddress,
            data.liquidityPoolAddresses,
            data.paths,
            _getLiquidityPoolOperator(data.liquidityPoolAddresses[0], liquidityPoolTokens),
            data.inputToken,
            data.amount,
            data.receiver == address(0) ? msg.sender : data.receiver
        );
    }

    function _collect(address[] memory tokenAddresses, uint256[] memory tokensAmounts, address operator, bool involvingETH) private {
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            _collect(tokenAddresses[i], tokensAmounts[i], operator, involvingETH);
        }
    }

    function _collect(address tokenAddress, uint256 tokenAmount, address operator, bool involvingETH) private {
        address realTokenAddress = involvingETH && tokenAddress == _ethereumAddress ? address(0) : tokenAddress;
        uint256 position = _tokenIndex[realTokenAddress];
        if(_tokensToTransfer.length == 0 || _tokensToTransfer[position] != realTokenAddress) {
            _tokenIndex[realTokenAddress] = (position = _tokensToTransfer.length);
            _tokensToTransfer.push(realTokenAddress);
            _operators.push(operator);
            _tokenAmounts.push(0);
        }
        _tokenAmounts[position] = _tokenAmounts[position] + tokenAmount;
    }

    function _transferToMeAndCheckAllowance(address[] memory tokens, uint256[] memory amounts, address operator, bool involvingETH) private {
        for(uint256 i = 0; i < tokens.length; i++) {
            _transferToMeAndCheckAllowance(involvingETH && tokens[i] == _ethereumAddress ? address(0) : tokens[i] , amounts[i], operator);
        }
    }

    function _transferToMeAndCheckAllowance() private {
        for(uint256 i = 0; i < _tokensToTransfer.length; i++) {
            _transferToMeAndCheckAllowance(_tokensToTransfer[i], _tokenAmounts[i], _operators[i]);
        }
    }

    function _flushBackAndClear(uint256[] memory collectedAmounts) private {
        for(uint256 i = 0; i < _tokensToTransfer.length; i++) {
            delete _tokenIndex[_tokensToTransfer[i]];
            _flushBack(_tokensToTransfer[i], _tokenAmounts[i], collectedAmounts.length > 0 ? collectedAmounts[i] : 0);
        }
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