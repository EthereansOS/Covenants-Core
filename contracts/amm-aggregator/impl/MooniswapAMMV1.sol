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

    function deposit(uint256[] memory amounts, uint256[] memory minAmounts) external payable returns(uint256 fairSupply);

    function withdraw(uint256 amount, uint256[] memory minReturns) external;

    function swap(address src, address dst, uint256 amount, uint256 minReturn, address referral) external payable returns(uint256 result);
}

contract MooniswapAMMV1 is AMM {

    address public immutable factory;

    constructor(address factoryAddress) AMM("Mooniswap", 1, address(0), 2, true) {
        factory = factoryAddress;
    }

    function _getLiquidityPoolOperator(uint256, address[] memory, bytes memory) internal override virtual view returns(address) {
        return address(0);
    }

    function _getSwapOperator(uint256, address[] memory, bytes memory) internal override virtual view returns(address) {
        return address(0);
    }

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

        Mooniswap mooniswap = IMooniFactory(factory).pools(tokens[0], tokens[1]);

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

    function _getLiquidityPoolCreator(address[] memory, uint256[] memory, bool, bytes memory) internal virtual view override returns(address) {
        return address(0);
    }

    function _createLiquidityPoolAndAddLiquidity(LiquidityPoolCreationData memory liquidityPoolCreationData) internal override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId, address[] memory orderedTokens) {

        Mooniswap mooniswap = IMooniFactory(factory).deploy(liquidityPoolCreationData.tokenAddresses[0], liquidityPoolCreationData.tokenAddresses[1]);
        address liquidityPoolAddress = address(mooniswap);
        liquidityPoolId = _toNumber(liquidityPoolAddress);
        orderedTokens = mooniswap.getTokens();

        tokensAmounts = new uint256[](orderedTokens.length);
        tokensAmounts[0] = liquidityPoolCreationData.amounts[orderedTokens[0] == liquidityPoolCreationData.tokenAddresses[0] ? 0 : 1];
        tokensAmounts[1] = liquidityPoolCreationData.amounts[orderedTokens[1] == liquidityPoolCreationData.tokenAddresses[1] ? 1 : 0];

        for(uint256 i = 0; i < orderedTokens.length; i++) {
            if(orderedTokens[i] != _ethereumAddress) {
                _safeApprove(orderedTokens[i], liquidityPoolAddress, tokensAmounts[i]);
            }
        }

        if(orderedTokens[0] != _ethereumAddress && orderedTokens[1] != _ethereumAddress) {
            mooniswap.deposit(tokensAmounts, liquidityPoolCreationData.minAmounts);
        } else {
            mooniswap.deposit{value : orderedTokens[0] == _ethereumAddress ? tokensAmounts[0] : tokensAmounts[1]}(tokensAmounts, liquidityPoolCreationData.minAmounts);
        }

        _safeTransfer(liquidityPoolAddress, liquidityPoolCreationData.receiver, liquidityPoolAmount = IERC20Full(liquidityPoolAddress).balanceOf(address(this)));
    }

    function _addLiquidity(ProcessedLiquidityPoolData memory data) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId) {
        address liquidityPoolAddress = _toAddress(liquidityPoolId = data.liquidityPoolId);
        Mooniswap mooniswap = Mooniswap(liquidityPoolAddress);

        liquidityPoolAmount = data.liquidityPoolAmount;
        tokensAmounts = data.tokensAmounts;

        for(uint256 i = 0; i < data.liquidityPoolTokens.length; i++) {
            if(data.liquidityPoolTokens[i] != _ethereumAddress) {
                _safeApprove(data.liquidityPoolTokens[i], liquidityPoolAddress, data.tokensAmounts[i]);
            }
        }

        if(data.liquidityPoolTokens[0] != _ethereumAddress && data.liquidityPoolTokens[1] != _ethereumAddress) {
            mooniswap.deposit(data.tokensAmounts, data.minAmounts);
        } else {
            mooniswap.deposit{value : data.liquidityPoolTokens[0] == _ethereumAddress ? data.tokensAmounts[0] : data.tokensAmounts[1]}(data.tokensAmounts, data.minAmounts);
        }
        _safeTransfer(liquidityPoolAddress, data.receiver, liquidityPoolAmount = IERC20Full(liquidityPoolAddress).balanceOf(address(this)));
    }

    function _removeLiquidity(ProcessedLiquidityPoolData memory data) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {

        Mooniswap(_toAddress(data.liquidityPoolId)).withdraw(liquidityPoolAmount = data.liquidityPoolAmount, data.minAmounts);

        tokensAmounts = new uint256[](data.tokensAmounts.length);
        for(uint256 i = 0; i < data.tokensAmounts.length; i++) {
            if(data.liquidityPoolTokens[i] != _ethereumAddress) {
                _safeTransfer(data.liquidityPoolTokens[i], data.receiver, data.tokensAmounts[i] = IERC20Full(data.liquidityPoolTokens[i]).balanceOf(address(this)));
            } else {
                (bool result,) = data.receiver.call{value:tokensAmounts[i] = address(this).balance}("");
                require(result, "ETH transfer failed");
            }
        }
    }

    function _swapLiquidity(ProcessedSwapData memory data) internal override virtual returns(uint256 outputAmount) {
        address[] memory liquidityPoolAddresses = _toAddresses(data.liquidityPoolIds);
        outputAmount = data.amount;
        for(uint256 i = 0; i < liquidityPoolAddresses.length; i++) {
            address inputToken = i == 0 ? data.inputToken : data.path[i - 1];
            if(inputToken != _ethereumAddress) {
                _safeApprove(inputToken, liquidityPoolAddresses[i], outputAmount);
            }
            if(inputToken == _ethereumAddress) {
                outputAmount = Mooniswap(liquidityPoolAddresses[i]).swap{value : outputAmount}(inputToken, data.path[i], outputAmount, data.minAmount, address(0));
            } else {
                outputAmount = Mooniswap(liquidityPoolAddresses[i]).swap(inputToken, data.path[i], outputAmount, data.minAmount, address(0));
            }
        }
        if(data.path[data.path.length - 1] == _ethereumAddress) {
            (bool result,) = data.receiver.call{value:outputAmount}("");
            require(result, "ETH transfer failed");
        } else {
            _safeTransfer(data.path[data.path.length - 1], data.receiver, outputAmount);
        }
    }
}