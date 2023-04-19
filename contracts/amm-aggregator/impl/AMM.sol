//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/IAMM.sol";
import "../../util/IERC20.sol";

abstract contract AMM is IAMM {

    struct ProcessedLiquidityPoolData {
        address liquidityPoolAddress;
        uint256 liquidityPoolAmount;
        address[] liquidityPoolTokens;
        uint256[] tokensAmounts;
        bool involvingETH;
        address liquidityPoolOperator;
        address receiver;
        uint256[] minAmounts;
    }

    struct ProcessedSwapData {
        bool enterInETH;
        bool exitInETH;
        address[] liquidityPoolAddresses;
        address[] path;
        address liquidityPoolOperator;
        address inputToken;
        uint256 amount;
        address receiver;
        uint256 minAmount;
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

        liquidityPoolAmount = calculatePercentage(liquidityPoolAmount, numerator, denominator);

        for(uint256 i = 0; i < tokensAmounts.length; i++) {
            tokensAmounts[i] = calculatePercentage(tokensAmounts[i], numerator, denominator);
        }
    }

    function byLiquidityPoolAmount(address liquidityPoolAddress, uint256 liquidityPoolAmount) view public virtual override returns(uint256[] memory tokensAmounts, address[] memory liquidityPoolTokens) {

        uint256 numerator = liquidityPoolAmount;
        uint256 denominator;

        (denominator, tokensAmounts, liquidityPoolTokens) = this.byLiquidityPool(liquidityPoolAddress);

        for(uint256 i = 0; i < tokensAmounts.length; i++) {
            tokensAmounts[i] = calculatePercentage(tokensAmounts[i], numerator, denominator);
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

        liquidityPoolAmount = calculatePercentage(liquidityPoolAmount, numerator, denominator);

        for(uint256 i = 0; i < tokensAmounts.length; i++) {
            tokensAmounts[i] = calculatePercentage(tokensAmounts[i], numerator, denominator);
        }
    }

    function calculatePercentage(uint256 amount, uint256 numerator, uint256 denominator) internal virtual pure returns(uint256) {
        return (amount * numerator) / denominator;
    }

    function createLiquidityPoolAndAddLiquidity(address[] memory tokenAddresses, uint256[] memory amounts, bool involvingETH, address receiver, uint256[] memory minAmounts) payable public virtual override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address liquidityPoolAddress, address[] memory orderedTokens) {
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
                    receiver,
                    minAmounts
                ));
                return (liquidityPoolAmount, tokensAmounts, liquidityPoolAddress, orderedTokens);
            }
        }
        address liquidityPoolCreator = _getLiquidityPoolCreator(tokenAddresses, amounts, involvingETH);
        _transferToMeAndCheckAllowance(tokenAddresses, amounts, liquidityPoolCreator, involvingETH);
        (liquidityPoolAmount, tokensAmounts, liquidityPoolAddress, orderedTokens) = _createLiquidityPoolAndAddLiquidity(tokenAddresses, amounts, involvingETH, liquidityPoolCreator, receiver, minAmounts);
        emit NewLiquidityPoolAddress(liquidityPoolAddress);
    }

    function addLiquidity(LiquidityPoolData memory liquidityPoolData) payable public virtual override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory liquidityPoolTokens) {
        ProcessedLiquidityPoolData memory processedLiquidityPoolData = _processLiquidityPoolData(liquidityPoolData);
        _transferToMeAndCheckAllowance(liquidityPoolTokens = processedLiquidityPoolData.liquidityPoolTokens, processedLiquidityPoolData.tokensAmounts, processedLiquidityPoolData.liquidityPoolOperator, liquidityPoolData.involvingETH);
        (liquidityPoolAmount, tokensAmounts) = _addLiquidity(processedLiquidityPoolData);
        _checkMinAmounts(tokensAmounts, processedLiquidityPoolData.minAmounts);
        _flushBack(liquidityPoolTokens);
    }

    function addLiquidityBatch(LiquidityPoolData[] memory liquidityPoolData) payable public virtual override returns(uint256[] memory liquidityPoolAmounts, uint256[][] memory tokensAmounts, address[][] memory liquidityPoolTokens) {
        liquidityPoolAmounts = new uint256[](liquidityPoolData.length);
        tokensAmounts = new uint256[][](liquidityPoolData.length);
        liquidityPoolTokens = new address[][](liquidityPoolData.length);
        ProcessedLiquidityPoolData[] memory processedLiquidityPoolDataArray = new ProcessedLiquidityPoolData[](liquidityPoolData.length);
        for(uint256 i = 0; i < liquidityPoolData.length; i++) {
            liquidityPoolTokens[i] = (processedLiquidityPoolDataArray[i] = _processLiquidityPoolData(liquidityPoolData[i])).liquidityPoolTokens;
            for(uint256 z = 0; z < liquidityPoolTokens[i].length; z++) {
                _collect(liquidityPoolTokens[i][z], processedLiquidityPoolDataArray[i].tokensAmounts[z], processedLiquidityPoolDataArray[i].liquidityPoolOperator, processedLiquidityPoolDataArray[i].involvingETH);
            }
        }
        _transferToMeAndCheckAllowance();
        _collect(_ethereumAddress, 0, address(0), false);
        for(uint256 i = 0; i < processedLiquidityPoolDataArray.length; i++) {
            (liquidityPoolAmounts[i], tokensAmounts[i]) = _addLiquidity(processedLiquidityPoolDataArray[i]);
            _checkMinAmounts(tokensAmounts[i], processedLiquidityPoolDataArray[i].minAmounts);
        }
        _flushBackAndClear();
    }

    function removeLiquidity(LiquidityPoolData memory liquidityPoolData) public virtual override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory liquidityPoolTokens) {
        ProcessedLiquidityPoolData memory processedLiquidityPoolData = _processLiquidityPoolData(liquidityPoolData);
        liquidityPoolTokens = processedLiquidityPoolData.liquidityPoolTokens;
        _transferToMeAndCheckAllowance(processedLiquidityPoolData.liquidityPoolAddress, processedLiquidityPoolData.liquidityPoolAmount, processedLiquidityPoolData.liquidityPoolOperator);
        (liquidityPoolAmount, tokensAmounts) = _removeLiquidity(processedLiquidityPoolData);
        _checkMinAmounts(tokensAmounts, processedLiquidityPoolData.minAmounts);
        _flushBack(processedLiquidityPoolData.liquidityPoolAddress);
    }

    function removeLiquidityBatch(LiquidityPoolData[] memory liquidityPoolData) public virtual override returns(uint256[] memory liquidityPoolAmounts, uint256[][] memory tokensAmounts, address[][] memory liquidityPoolTokens) {
        liquidityPoolAmounts = new uint256[](liquidityPoolData.length);
        tokensAmounts = new uint256[][](liquidityPoolData.length);
        liquidityPoolTokens = new address[][](liquidityPoolData.length);
        ProcessedLiquidityPoolData[] memory processedLiquidityPoolDataArray = new ProcessedLiquidityPoolData[](liquidityPoolData.length);
        for(uint256 i = 0; i < liquidityPoolData.length; i++) {
            processedLiquidityPoolDataArray[i] = _processLiquidityPoolData(liquidityPoolData[i]);
            liquidityPoolTokens[i] = processedLiquidityPoolDataArray[i].liquidityPoolTokens;
            _collect(processedLiquidityPoolDataArray[i].liquidityPoolAddress, processedLiquidityPoolDataArray[i].liquidityPoolAmount, processedLiquidityPoolDataArray[i].liquidityPoolOperator, false);
        }
        _transferToMeAndCheckAllowance();
        for(uint256 i = 0; i < processedLiquidityPoolDataArray.length; i++) {
            (liquidityPoolAmounts[i], tokensAmounts[i]) = _removeLiquidity(processedLiquidityPoolDataArray[i]);
            _checkMinAmounts(tokensAmounts[i], processedLiquidityPoolDataArray[i].minAmounts);
        }
        _flushBackAndClear();
    }

    function swapLiquidity(SwapData memory swapData) payable public virtual override returns(uint256 outputAmount) {
        ProcessedSwapData memory processedSwapData = _processSwapData(swapData);
        _transferToMeAndCheckAllowance(processedSwapData.inputToken == _ethereumAddress && processedSwapData.enterInETH ? address(0) : processedSwapData.inputToken, processedSwapData.amount, processedSwapData.liquidityPoolOperator);
        outputAmount = _swapLiquidity(processedSwapData);
        _checkMinAmount(outputAmount, processedSwapData.minAmount);
        _flushBack(processedSwapData.enterInETH ? address(0) : processedSwapData.inputToken);
    }

    function swapLiquidityBatch(SwapData[] memory swapData) payable public virtual override returns(uint256[] memory outputAmounts) {
        ProcessedSwapData[] memory processedSwapDatas = new ProcessedSwapData[](swapData.length);
        outputAmounts = new uint256[](swapData.length);
        for(uint256 i = 0; i < swapData.length; i++) {
            processedSwapDatas[i] = _processSwapData(swapData[i]);
            _collect(processedSwapDatas[i].inputToken, processedSwapDatas[i].amount, processedSwapDatas[i].liquidityPoolOperator, processedSwapDatas[i].enterInETH);
        }
        _transferToMeAndCheckAllowance();
        for(uint256 i = 0; i < swapData.length; i++) {
            outputAmounts[i] = _swapLiquidity(processedSwapDatas[i]);
            _checkMinAmount(outputAmounts[i], processedSwapDatas[i].minAmount);
        }
        _flushBackAndClear();
    }

    function _getLiquidityPoolOperator(address liquidityPoolAddress, address[] memory liquidityPoolTokens) internal virtual view returns(address);

    function _addLiquidity(ProcessedLiquidityPoolData memory processedLiquidityPoolData) internal virtual returns(uint256, uint256[] memory);

    function _removeLiquidity(ProcessedLiquidityPoolData memory processedLiquidityPoolData) internal virtual returns(uint256, uint256[] memory);

    function _swapLiquidity(ProcessedSwapData memory data) internal virtual returns(uint256 outputAmount);

    function _getLiquidityPoolCreator(address[] memory tokenAddresses, uint256[] memory amounts, bool involvingETH) internal virtual view returns(address);

    function _createLiquidityPoolAndAddLiquidity(address[] memory tokenAddresses, uint256[] memory amounts, bool involvingETH, address operator, address receiver, uint256[] memory minAmounts) internal virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address liquidityPoolAddress, address[] memory orderedTokens);

    function _processLiquidityPoolData(LiquidityPoolData memory liquidityPoolData) internal view returns(ProcessedLiquidityPoolData memory) {
        require(liquidityPoolData.amount > 0, "Zero amount");
        uint256[] memory tokensAmounts;
        address[] memory liquidityPoolTokens;
        uint256 liquidityPoolAmount;
        if(liquidityPoolData.amountIsLiquidityPool) {
            (tokensAmounts, liquidityPoolTokens) = byLiquidityPoolAmount(liquidityPoolData.liquidityPoolAddress, liquidityPoolAmount = liquidityPoolData.amount);
        } else {
            (liquidityPoolAmount, tokensAmounts, liquidityPoolTokens) = byTokenAmount(liquidityPoolData.liquidityPoolAddress, liquidityPoolData.tokenAddress, liquidityPoolData.amount);
        }
        bool involvingETH = liquidityPoolData.involvingETH;
        if(_ethereumAddress == address(0)) {
            involvingETH = false;
            for(uint256 i = 0; i < liquidityPoolTokens.length; i++) {
                if(liquidityPoolTokens[i] == address(0)) {
                    involvingETH = true;
                }
            }
        }
        return ProcessedLiquidityPoolData(
            liquidityPoolData.liquidityPoolAddress,
            liquidityPoolAmount,
            liquidityPoolTokens,
            tokensAmounts,
            involvingETH,
            _getLiquidityPoolOperator(liquidityPoolData.liquidityPoolAddress, liquidityPoolTokens),
            liquidityPoolData.receiver == address(0) ? msg.sender : liquidityPoolData.receiver,
            liquidityPoolData.minAmounts
        );
    }

    function _processSwapData(SwapData memory swapData) internal view returns(ProcessedSwapData memory) {
        require(swapData.amount > 0, "Zero amount");
        require(swapData.path.length > 0 && swapData.liquidityPoolAddresses.length == swapData.path.length, "Invalid length");
        ( , ,address[] memory liquidityPoolTokens) = this.byLiquidityPool(swapData.liquidityPoolAddresses[0]);
        return ProcessedSwapData(
            swapData.enterInETH && swapData.inputToken == _ethereumAddress,
            swapData.exitInETH && swapData.path[swapData.path.length - 1] == _ethereumAddress,
            swapData.liquidityPoolAddresses,
            swapData.path,
            _getLiquidityPoolOperator(swapData.liquidityPoolAddresses[0], liquidityPoolTokens),
            swapData.inputToken,
            swapData.amount,
            swapData.receiver == address(0) ? msg.sender : swapData.receiver,
            swapData.minAmount
        );
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

    function _transferToMeAndCheckAllowance(address[] memory tokens, uint256[] memory amounts, address operator, bool involvingETH) internal {
        for(uint256 i = 0; i < tokens.length; i++) {
            _transferToMeAndCheckAllowance(involvingETH && tokens[i] == _ethereumAddress ? address(0) : tokens[i] , amounts[i], operator);
        }
    }

    function _transferToMeAndCheckAllowance(address tokenAddress, uint256 value, address operator) internal {
        _transferToMe(tokenAddress, value);
        _checkAllowance(tokenAddress, value, operator);
    }

    function _transferToMeAndCheckAllowance() private {
        for(uint256 i = 0; i < _tokensToTransfer.length; i++) {
            _transferToMeAndCheckAllowance(_tokensToTransfer[i], _tokenAmounts[i], _operators[i]);
        }
    }

    function _flushBackAndClear() private {
        for(uint256 i = 0; i < _tokensToTransfer.length; i++) {
            delete _tokenIndex[_tokensToTransfer[i]];
            _flushBack(_tokensToTransfer[i]);
        }
        _flushBack(address(0));
        delete _tokensToTransfer;
        delete _operators;
        delete _tokenAmounts;
    }

    function _transferToMe(address tokenAddress, uint256 value) internal virtual {
        if(tokenAddress == address(0)) {
            require(msg.value == value, "Incorrect eth value");
            return;
        }
        _safeTransferFrom(tokenAddress, msg.sender, address(this), value);
    }

    function _flushBack(address[] memory tokenAddresses) internal {
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            _flushBack(tokenAddresses[i]);
        }
        _flushBack(address(0));
    }

    function _flushBack(address tokenAddress) internal {
        uint256 amount = tokenAddress == address(0) ? address(this).balance : IERC20(tokenAddress).balanceOf(address(this));
        if(amount == 0) {
            return;
        }
        if(tokenAddress == address(0)) {
            if(address(this).balance >= amount) {
                (bool result,) = msg.sender.call{value:amount}("");
                require(result, "ETH transfer failed");
            }
            return;
        }
        if(IERC20(tokenAddress).balanceOf(address(this)) >= amount) {
            _safeTransfer(tokenAddress, msg.sender, amount);
        }
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

    function _checkMinAmounts(uint256[] memory amounts, uint256[] memory minAmounts) private pure {
        for(uint256 i = 0; i < amounts.length; i++) {
            _checkMinAmount(amounts[i], minAmounts[i]);
        }
    }

    function _checkMinAmount(uint256 amount, uint256 minAmount) private pure {
        require(amount >= minAmount, "too little received");
    }
}