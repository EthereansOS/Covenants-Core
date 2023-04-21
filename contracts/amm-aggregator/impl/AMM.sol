//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/IAMM.sol";
import { IERC20Full } from "@ethereansos/swissknife/contracts/lib/GeneralUtilities.sol";

abstract contract AMM is IAMM {
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

    mapping(address => uint256) internal _tokenIndex;
    address[] internal _tokensToTransfer;
    address[] internal _operators;
    uint256[] internal _tokenAmounts;

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

    receive() external payable {
    }

    function info() public view override virtual returns(string memory name, uint256 version) {
        return (_name, _version);
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
        _transferToMeAndCheckAllowance(liquidityPoolCreationParams.tokenAddresses, liquidityPoolCreationParams.amounts, liquidityPoolCreator, liquidityPoolCreationParams.involvingETH);
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
        _transferToMeAndCheckAllowance(liquidityPoolTokens = processedLiquidityPoolParams.liquidityPoolTokens, processedLiquidityPoolParams.tokensAmounts, processedLiquidityPoolParams.liquidityPoolOperator, liquidityPoolParams.involvingETH);
        (liquidityPoolAmount, liquidityPoolTokenAmounts, liquidityPoolId) = _addLiquidity(processedLiquidityPoolParams);
        _checkMinAmounts(liquidityPoolTokenAmounts, processedLiquidityPoolParams.minAmounts);
        require(block.timestamp < processedLiquidityPoolParams.deadline, "too late");
        _flushBack(liquidityPoolTokens);
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
        _transferToMeAndCheckAllowance();
        _collect(_ethereumAddress, 0, address(0), false);
        for(uint256 i = 0; i < processedLiquidityPoolDataArray.length; i++) {
            (liquidityPoolAmounts[i], liquidityPoolTokenAmounts[i], liquidityPoolIds[i]) = _addLiquidity(processedLiquidityPoolDataArray[i]);
            _checkMinAmounts(liquidityPoolTokenAmounts[i], processedLiquidityPoolDataArray[i].minAmounts);
            require(block.timestamp < processedLiquidityPoolDataArray[i].deadline, "too late");
        }
        _flushBackAndClear();
    }

    function removeLiquidity(LiquidityPoolParams memory liquidityPoolParams) public override virtual returns(uint256 removedLiquidityPoolAmount, uint256[] memory removedLiquidityPoolTokenAmounts, address[] memory liquidityPoolTokens) {
        ProcessedLiquidityPoolParams memory processedLiquidityPoolParams = _processLiquidityPoolParams(liquidityPoolParams);
        liquidityPoolTokens = processedLiquidityPoolParams.liquidityPoolTokens;
        address liquidityPoolAddress = _toAddress(processedLiquidityPoolParams.liquidityPoolId);
        _transferToMeAndCheckAllowance(liquidityPoolAddress, processedLiquidityPoolParams.liquidityPoolAmount, processedLiquidityPoolParams.liquidityPoolOperator);
        (removedLiquidityPoolAmount, removedLiquidityPoolTokenAmounts) = _removeLiquidity(processedLiquidityPoolParams);
        _checkMinAmounts(removedLiquidityPoolTokenAmounts, processedLiquidityPoolParams.minAmounts);
        require(block.timestamp < processedLiquidityPoolParams.deadline, "too late");
        _flushBack(liquidityPoolAddress);
    }

    function removeLiquidityBatch(LiquidityPoolParams[] memory liquidityPoolParams) public override virtual returns(uint256[] memory removedLiquidityPoolAmounts, uint256[][] memory removedLiquidityPoolTokenAmounts, address[][] memory liquidityPoolTokens) {
        removedLiquidityPoolAmounts = new uint256[](liquidityPoolParams.length);
        removedLiquidityPoolTokenAmounts = new uint256[][](liquidityPoolParams.length);
        liquidityPoolTokens = new address[][](liquidityPoolParams.length);
        ProcessedLiquidityPoolParams[] memory processedLiquidityPoolDataArray = new ProcessedLiquidityPoolParams[](liquidityPoolParams.length);
        for(uint256 i = 0; i < liquidityPoolParams.length; i++) {
            processedLiquidityPoolDataArray[i] = _processLiquidityPoolParams(liquidityPoolParams[i]);
            liquidityPoolTokens[i] = processedLiquidityPoolDataArray[i].liquidityPoolTokens;
            _collect(_toAddress(processedLiquidityPoolDataArray[i].liquidityPoolId), processedLiquidityPoolDataArray[i].liquidityPoolAmount, processedLiquidityPoolDataArray[i].liquidityPoolOperator, false);
        }
        _transferToMeAndCheckAllowance();
        for(uint256 i = 0; i < processedLiquidityPoolDataArray.length; i++) {
            (removedLiquidityPoolAmounts[i], removedLiquidityPoolTokenAmounts[i]) = _removeLiquidity(processedLiquidityPoolDataArray[i]);
            _checkMinAmounts(removedLiquidityPoolTokenAmounts[i], processedLiquidityPoolDataArray[i].minAmounts);
            require(block.timestamp < processedLiquidityPoolDataArray[i].deadline, "too late");
        }
        _flushBackAndClear();
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
        _transferToMeAndCheckAllowance(processedSwapParams.inputToken == _ethereumAddress && processedSwapParams.enterInETH ? address(0) : processedSwapParams.inputToken, processedSwapParams.amount, processedSwapParams.liquidityPoolOperator);
        receivedValue = _swapLiquidity(processedSwapParams);
        _checkMinAmount(receivedValue, processedSwapParams.minAmount);
        require(block.timestamp < swapParams.deadline, "too late");
        _flushBack(processedSwapParams.enterInETH ? address(0) : processedSwapParams.inputToken);
    }

    function swapBatch(SwapParams[] memory swapParams) public override virtual payable returns(uint256[] memory receivedValues) {
        ProcessedSwapParams[] memory processedSwapDatas = new ProcessedSwapParams[](swapParams.length);
        receivedValues = new uint256[](swapParams.length);
        for(uint256 i = 0; i < swapParams.length; i++) {
            processedSwapDatas[i] = _processSwapParams(swapParams[i]);
            _collect(processedSwapDatas[i].inputToken, processedSwapDatas[i].amount, processedSwapDatas[i].liquidityPoolOperator, processedSwapDatas[i].enterInETH);
        }
        _transferToMeAndCheckAllowance();
        for(uint256 i = 0; i < swapParams.length; i++) {
            receivedValues[i] = _swapLiquidity(processedSwapDatas[i]);
            _checkMinAmount(receivedValues[i], processedSwapDatas[i].minAmount);
        }
        _flushBackAndClear();
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

    function _swapLiquidity(ProcessedSwapParams memory processedSwapParams) internal virtual returns(uint256 outputAmount);

    function _getLiquidityPoolCreator(address[] memory tokenAddresses, uint256[] memory amounts, bool involvingETH, bytes memory additionalData) internal virtual view returns(address);

    function _createLiquidityPoolAndAddLiquidity(LiquidityPoolCreationParams memory liquidityPoolCreationParams) internal virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId, address[] memory orderedTokens);

    function _getSwapOutput(uint256 amount, uint256[] memory liquidityPoolIds, address[] memory path) view internal virtual returns(uint256);
    function _getSwapInput(uint256 amount, uint256[] memory liquidityPoolIds, address[] memory path) view internal virtual returns(uint256);

    function _checkAddLiquidityAdditionalData(ProcessedLiquidityPoolParams[] memory processedLiquidityPoolParams) internal virtual view;
    function _checkRemoveLiquidityAdditionalData(ProcessedLiquidityPoolParams[] memory processedLiquidityPoolParams) internal virtual view;
    function _checkSwapAdditionalData(ProcessedSwapParams[] memory processedSwapParams) internal virtual view;

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

    function _collect(address tokenAddress, uint256 tokenAmount, address operator, bool involvingETH) internal {
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

    function _transferToMeAndCheckAllowance(address tokenAddress, uint256 amount, address operator) internal {
        _transferToMe(tokenAddress, amount);
        _checkAllowance(tokenAddress, amount, operator);
    }

    function _transferToMeAndCheckAllowance() internal {
        for(uint256 i = 0; i < _tokensToTransfer.length; i++) {
            _transferToMeAndCheckAllowance(_tokensToTransfer[i], _tokenAmounts[i], _operators[i]);
        }
    }

    function _flushBackAndClear() internal {
        for(uint256 i = 0; i < _tokensToTransfer.length; i++) {
            delete _tokenIndex[_tokensToTransfer[i]];
            _flushBack(_tokensToTransfer[i]);
        }
        _flushBack(address(0));
        delete _tokensToTransfer;
        delete _operators;
        delete _tokenAmounts;
    }

    function _transferToMe(address tokenAddress, uint256 amount) internal virtual {
        if(tokenAddress == address(0)) {
            require(msg.value == amount, "Incorrect eth amount");
            return;
        }
        _safeTransferFrom(tokenAddress, msg.sender, address(this), amount);
    }

    function _flushBack(address[] memory tokenAddresses) internal {
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            _flushBack(tokenAddresses[i]);
        }
        _flushBack(address(0));
    }

    function _flushBack(address tokenAddress) internal {
        uint256 amount = tokenAddress == address(0) ? address(this).balance : IERC20Full(tokenAddress).balanceOf(address(this));
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
        if(IERC20Full(tokenAddress).balanceOf(address(this)) >= amount) {
            _safeTransfer(tokenAddress, msg.sender, amount);
        }
    }

    function _checkAllowance(address tokenAddress, uint256 amount, address operator) internal {
        if(tokenAddress == address(0) || operator == address(0)) {
            return;
        }
        IERC20Full token = IERC20Full(tokenAddress);
        if(token.allowance(address(this), operator) <= amount) {
            _safeApprove(tokenAddress, operator, token.totalSupply());
        }
    }

    function _safeApprove(address erc20TokenAddress, address to, uint256 amount) internal {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20Full(erc20TokenAddress).approve.selector, to, amount));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'APPROVE_FAILED');
    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 amount) internal {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20Full(erc20TokenAddress).transfer.selector, to, amount));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFER_FAILED');
    }

    function _safeTransferFrom(address erc20TokenAddress, address from, address to, uint256 amount) internal {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20Full(erc20TokenAddress).transferFrom.selector, from, to, amount));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFERFROM_FAILED');
    }

    function _call(address location, bytes memory payload) internal returns(bytes memory returnData) {
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
}