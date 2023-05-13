//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AMM.sol";

contract IMooniFactory {

    mapping(address => mapping(address => Mooniswap)) public pools;

    function deploy(address tokenA, address tokenB) external returns(Mooniswap pool) {}
    function sortTokens(address tokenA, address tokenB) external pure returns(address, address) {}
}

interface Mooniswap {

    function fee() external view returns(uint256);

    function getTokens() external view returns(address[] memory);

    function decayPeriod() external pure returns(uint256);

    function getBalanceForAddition(address token) external view returns(uint256);

    function getBalanceForRemoval(address token) external view returns(uint256);

    function getReturn(address src, address dst, uint256 amount) external view returns(uint256);

    function deposit(uint256[] memory amounts, uint256[] memory amountsMin) external payable returns(uint256 fairSupply);

    function withdraw(uint256 amount, uint256[] memory minReturns) external;

    function swap(address src, address dst, uint256 amount, uint256 minReturn, address referral) external payable returns(uint256 result);
}

contract MooniswapAMMV1 is AMM {
    using TransferUtilities for address;

    address private _factoryAddress;

    constructor(address factoryAddress) AMM("Mooniswap", 1, address(0), 2, true, 20, address(0)) {
        _factoryAddress = factoryAddress;
    }

    function _getLiquidityPoolCreationOperator(address[] memory, uint256[] memory, bool, bytes memory) internal virtual view override returns(address) {
        return address(0);
    }

    function _getLiquidityPoolOperator(uint256, address[] memory, bytes memory) internal override virtual view returns(address) {
        return address(0);
    }

    function _getSwapOperator(uint256, address[] memory, bytes memory) internal override virtual view returns(address) {
        return address(0);
    }

    function checkByTokensAdditionalData(address[] calldata tokens, bytes calldata additionalData) external override view {}
    function checkAddLiquidityEnsuringPoolAdditionalData(LiquidityPoolCreationParams[] calldata liquidityPoolCreationParams) external override view {}
    function _checkAddLiquidityAdditionalData(ProcessedLiquidityPoolParams[] memory) internal override view {}
    function _checkRemoveLiquidityAdditionalData(ProcessedLiquidityPoolParams[] memory) internal override view {}
    function _checkSwapAdditionalData(ProcessedSwapParams[] memory) internal override view {}

    function byLiquidityPool(uint256 liquidityPoolId) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory tokenAddresses) {

        address liquidityPoolAddress = _toAddress(liquidityPoolId);
        Mooniswap mooniswap = Mooniswap(liquidityPoolAddress);

        liquidityPoolAmount = IERC20Full(liquidityPoolAddress).totalSupply();

        tokensAmounts = new uint256[]((tokenAddresses = mooniswap.getTokens()).length);
        for(uint256 i = 0; i < tokensAmounts.length; i++) {
            tokensAmounts[i] = mooniswap.getBalanceForRemoval(tokenAddresses[i]);
        }
    }

    function byTokens(address[] memory tokens, bytes calldata) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId, address[] memory orderedTokens) {

        Mooniswap mooniswap = IMooniFactory(_factoryAddress).pools(tokens[0], tokens[1]);

        if(address(mooniswap) == address(0)) {
            return (liquidityPoolAmount, tokensAmounts, liquidityPoolId, orderedTokens);
        }

        orderedTokens = mooniswap.getTokens();

        liquidityPoolId = _toNumber(address(mooniswap));
        liquidityPoolAmount = IERC20Full(address(mooniswap)).totalSupply();

        tokensAmounts = new uint256[](orderedTokens.length);
        for(uint256 i = 0; i < tokensAmounts.length; i++) {
            tokensAmounts[i] = mooniswap.getBalanceForRemoval(orderedTokens[i]);
        }
    }

    function _getSwapOutput(uint256 value, uint256[] memory liquidityPoolIds, address[] memory path) view internal override returns(uint256) {
        address[] memory liquidityPoolAddresses = _toAddresses(liquidityPoolIds);
        uint256[] memory values = new uint256[](path.length);
        values[0] = value;
        for(uint256 i = 1 ; i < path.length; i++) {
            values[i] = Mooniswap(liquidityPoolAddresses[i - 1]).getReturn(path[i - 1], path[i], values[i - 1]);
        }
        return values[values.length - 1];
    }

    function _getSwapInput(uint256 value, uint256[] memory liquidityPoolIds, address[] memory path) view internal override returns(uint256) {
        address[] memory liquidityPoolAddresses = _toAddresses(liquidityPoolIds);
        uint256[] memory values = new uint256[](path.length);
        values[values.length - 1] = value;
        for(uint256 i = values.length - 2 ; i >= 0; i--) {
            values[i] = Mooniswap(liquidityPoolAddresses[i]).getReturn(path[i + 1], path[i], values[i + 1]);
        }
        return values[0];
    }

    function _createLiquidityPoolAndAddLiquidity(LiquidityPoolCreationParams memory liquidityPoolCreationData) internal override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId, address[] memory orderedTokens) {

        Mooniswap mooniswap = IMooniFactory(_factoryAddress).deploy(liquidityPoolCreationData.tokenAddresses[0], liquidityPoolCreationData.tokenAddresses[1]);

        orderedTokens = mooniswap.getTokens();

        tokensAmounts = new uint256[](orderedTokens.length);
        tokensAmounts[0] = liquidityPoolCreationData.amounts[orderedTokens[0] == liquidityPoolCreationData.tokenAddresses[0] ? 0 : 1];
        tokensAmounts[1] = liquidityPoolCreationData.amounts[orderedTokens[1] == liquidityPoolCreationData.tokenAddresses[1] ? 1 : 0];

        (liquidityPoolAmount, liquidityPoolId) = _addLiquidity(address(mooniswap), orderedTokens, tokensAmounts, liquidityPoolCreationData.amountsMin, liquidityPoolCreationData.receiver, true);
    }

    function _addLiquidity(ProcessedLiquidityPoolParams memory processedLiquidityPoolParams) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId) {
        (liquidityPoolAmount, liquidityPoolId) = _addLiquidity(_toAddress(processedLiquidityPoolParams.liquidityPoolId), processedLiquidityPoolParams.liquidityPoolTokens, tokensAmounts = processedLiquidityPoolParams.tokensAmounts, processedLiquidityPoolParams.amountsMin, processedLiquidityPoolParams.receiver, false);
    }

    function _addLiquidity(address liquidityPoolAddress, address[] memory tokens, uint256[] memory tokensAmounts, uint256[] memory amountsMin, address receiver, bool isNew) private returns(uint256 liquidityPoolAmount, uint256 liquidityPoolId) {

        liquidityPoolId = _toNumber(liquidityPoolAddress);

        if(!isNew) {
            liquidityPoolAmount = liquidityPoolAddress.balanceOf(address(this));
        }

        address ethereumAddress = _ethereumAddress;
        for(uint256 i = 0; i < tokens.length; i++) {
            if(tokens[i] != ethereumAddress) {
                tokens[i].safeApprove(liquidityPoolAddress, tokensAmounts[i]);
            }
        }

        Mooniswap(liquidityPoolAddress).deposit{value : tokens[0] == ethereumAddress ? tokensAmounts[0] : tokens[1] == ethereumAddress ? tokensAmounts[1] : 0}(tokensAmounts, amountsMin);

        liquidityPoolAmount = liquidityPoolAddress.balanceOf(address(this)) - liquidityPoolAmount;

        if(receiver != address(this)) {
            liquidityPoolAddress.safeTransfer(receiver, liquidityPoolAmount);
        }
    }

    function _removeLiquidity(ProcessedLiquidityPoolParams memory data) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {

        uint256[] memory balancesBefore = _balanceOf(data.liquidityPoolTokens);

        Mooniswap(_toAddress(data.liquidityPoolId)).withdraw(liquidityPoolAmount = data.liquidityPoolAmount, data.amountsMin);

        tokensAmounts = _balanceOf(data.liquidityPoolTokens);

        for(uint256 i = 0; i < tokensAmounts.length; i++) {
            tokensAmounts[i] -= balancesBefore[i];
            if(data.receiver == address(this)) {
                continue;
            }
            data.liquidityPoolTokens[i].safeTransfer(data.receiver, data.tokensAmounts[i]);
        }
    }

    function _swap(ProcessedSwapParams memory processedSwapParams) internal override virtual returns(uint256 outputAmount) {
        address[] memory liquidityPoolAddresses = _toAddresses(processedSwapParams.liquidityPoolIds);
        outputAmount = processedSwapParams.amount;
        address ethereumAddress = _ethereumAddress;
        for(uint256 i = 0; i < liquidityPoolAddresses.length; i++) {
            address inputToken = i == 0 ? processedSwapParams.inputToken : processedSwapParams.path[i - 1];
            bool isETH = inputToken == ethereumAddress;
            if(!isETH) {
                inputToken.safeApprove(liquidityPoolAddresses[i], outputAmount);
            }
            outputAmount = Mooniswap(liquidityPoolAddresses[i]).swap{value : isETH ? outputAmount : 0}(inputToken, processedSwapParams.path[i], outputAmount, i == liquidityPoolAddresses.length - 1 ? processedSwapParams.minAmount : 0, address(0));
        }
        if(processedSwapParams.receiver != address(this)) {
            processedSwapParams.path[processedSwapParams.path.length - 1].safeTransfer(processedSwapParams.receiver, outputAmount);
        }
    }
}