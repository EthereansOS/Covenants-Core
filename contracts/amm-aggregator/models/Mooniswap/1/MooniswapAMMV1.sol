//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./IMooniswapAMMV1.sol";
import "../../../common/AMM.sol";

contract MooniswapAMMV1 is IMooniswapAMMV1, AMM {

    address public override immutable factory;

    constructor(address factoryAddress) AMM("MooniswapAMM", 1, address(0), 2, true) {
        factory = factoryAddress;
    }

    function _getLiquidityPoolOperator(address, address[] memory) internal override virtual view returns(address) {
        return address(0);
    }

    function byLiquidityPool(address liquidityPoolAddress) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory tokenAddresses) {

        Mooniswap mooniswap = Mooniswap(liquidityPoolAddress);

        liquidityPoolAmount = IERC20(liquidityPoolAddress).totalSupply();

        tokensAmounts = new uint256[]((tokenAddresses = mooniswap.getTokens()).length);
        for(uint256 i = 0; i < tokensAmounts.length; i++) {
            tokensAmounts[i] = mooniswap.getBalanceForRemoval(tokenAddresses[i]);
        }
    }

    function byTokens(address[] memory tokens) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address liquidityPoolAddress, address[] memory orderedTokens) {

        Mooniswap mooniswap = IMooniFactory(factory).pools(tokens[0], tokens[1]);

        if(address(mooniswap) == address(0)) {
            return (liquidityPoolAmount, tokensAmounts, liquidityPoolAddress, orderedTokens);
        }

        orderedTokens = mooniswap.getTokens();

        liquidityPoolAmount = IERC20(liquidityPoolAddress = address(mooniswap)).totalSupply();

        tokensAmounts = new uint256[](orderedTokens.length);
        for(uint256 i = 0; i < tokensAmounts.length; i++) {
            tokensAmounts[i] = mooniswap.getBalanceForRemoval(orderedTokens[i]);
        }
    }

    function _getLiquidityPoolCreator(address[] memory, uint256[] memory, bool) internal virtual view override returns(address) {
        return address(0);
    }

    function _createLiquidityPoolAndAddLiquidity(address[] memory tokenAddresses, uint256[] memory amounts, bool, address, address receiver) internal virtual override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address liquidityPoolAddress, address[] memory orderedTokens) {

        tokensAmounts = new uint256[](2);

        Mooniswap mooniswap = IMooniFactory(factory).deploy(tokenAddresses[0], tokenAddresses[1]);
        liquidityPoolAddress = address(mooniswap);
        orderedTokens = mooniswap.getTokens();

        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            if(tokenAddresses[i] != _ethereumAddress) {
                _safeApprove(tokenAddresses[i], liquidityPoolAddress, amounts[i]);
            }
        }

        if(tokenAddresses[0] != _ethereumAddress && tokenAddresses[1] != _ethereumAddress) {
            mooniswap.deposit(amounts, new uint256[](amounts.length));
        } else {
            mooniswap.deposit{value : tokenAddresses[0] == _ethereumAddress ? amounts[0] : amounts[1]}(amounts, new uint256[](amounts.length));
        }

        _safeTransfer(liquidityPoolAddress, receiver, liquidityPoolAmount = IERC20(liquidityPoolAddress).totalSupply());
    }

    function _addLiquidity(ProcessedLiquidityPoolData memory data) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {

        Mooniswap mooniswap = Mooniswap(data.liquidityPoolAddress);

        liquidityPoolAmount = data.liquidityPoolAmount;
        tokensAmounts = data.tokensAmounts;

        for(uint256 i = 0; i < data.liquidityPoolTokens.length; i++) {
            if(data.liquidityPoolTokens[i] != _ethereumAddress) {
                _safeApprove(data.liquidityPoolTokens[i], data.liquidityPoolAddress, data.tokensAmounts[i]);
            }
        }

        if(data.liquidityPoolTokens[0] != _ethereumAddress && data.liquidityPoolTokens[1] != _ethereumAddress) {
            mooniswap.deposit(data.tokensAmounts, new uint256[](data.tokensAmounts.length));
        } else {
            mooniswap.deposit{value : data.liquidityPoolTokens[0] == _ethereumAddress ? data.tokensAmounts[0] : data.tokensAmounts[1]}(data.tokensAmounts, new uint256[](data.tokensAmounts.length));
        }
        _safeTransfer(data.liquidityPoolAddress, data.receiver, liquidityPoolAmount);
    }

    function _removeLiquidity(ProcessedLiquidityPoolData memory data) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {

        Mooniswap(data.liquidityPoolAddress).withdraw(liquidityPoolAmount = data.liquidityPoolAmount, new uint256[](2));

        tokensAmounts = new uint256[](data.tokensAmounts.length);
        for(uint256 i = 0; i < data.tokensAmounts.length; i++) {
            if(data.liquidityPoolTokens[i] != _ethereumAddress) {
                _safeTransfer(data.liquidityPoolTokens[i], data.receiver, data.tokensAmounts[i] = IERC20(data.liquidityPoolTokens[i]).balanceOf(address(this)));
            } else {
                payable(data.receiver).transfer(tokensAmounts[i] = address(this).balance);
            }
        }
    }

    function _swapLiquidity(ProcessedSwapData memory data) internal override virtual returns(uint256 outputAmount) {
        outputAmount = data.amount;
        for(uint256 i = 0; i < data.liquidityPoolAddresses.length; i++) {
            address inputToken = i == 0 ? data.inputToken : data.paths[i - 1];
            if(inputToken != _ethereumAddress) {
                _safeApprove(inputToken, data.liquidityPoolAddresses[i], outputAmount);
            }
            if(inputToken == _ethereumAddress) {
                outputAmount = Mooniswap(data.liquidityPoolAddresses[i]).swap{value : outputAmount}(inputToken, data.paths[i], outputAmount, 1, address(0));
            } else {
                outputAmount = Mooniswap(data.liquidityPoolAddresses[i]).swap(inputToken, data.paths[i], outputAmount, 1, address(0));
            }
        }
        if(data.paths[data.paths.length - 1] == _ethereumAddress) {
            payable(data.receiver).transfer(outputAmount);
        } else {
            _safeTransfer(data.paths[data.paths.length - 1], data.receiver, outputAmount);
        }
    }
}