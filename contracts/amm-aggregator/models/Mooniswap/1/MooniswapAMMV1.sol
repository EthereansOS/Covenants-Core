//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./IMooniswapAMMV1.sol";
import "../../../common/AMM.sol";

contract MooniswapAMMV1 is IMooniswapAMMV1, AMM {

    address public override immutable factory;

    constructor(address factoryAddress) AMM("Mooniswap", 1, address(0), 2, true) {
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

    function getSwapOutput(address tokenAddress, uint256 tokenAmount, address[] calldata liquidityPoolAddresses, address[] calldata path) view public virtual override returns(uint256[] memory realAmounts) {
        realAmounts = new uint256[](path.length + 1);
        realAmounts[0] = tokenAmount;
        for(uint256 i = 0 ; i < path.length; i++) {
            realAmounts[i + 1] = Mooniswap(liquidityPoolAddresses[i]).getReturn(i == 0 ? tokenAddress : path[i - 1], path[i], realAmounts[i]);
        }
    }

    function _getLiquidityPoolCreator(address[] memory, uint256[] memory, bool) internal virtual view override returns(address) {
        return address(0);
    }

    function _createLiquidityPoolAndAddLiquidity(address[] memory tokenAddresses, uint256[] memory amounts, bool, address, address receiver) internal virtual override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address liquidityPoolAddress, address[] memory orderedTokens) {

        Mooniswap mooniswap = IMooniFactory(factory).deploy(tokenAddresses[0], tokenAddresses[1]);
        liquidityPoolAddress = address(mooniswap);
        orderedTokens = mooniswap.getTokens();

        tokensAmounts = new uint256[](orderedTokens.length);
        tokensAmounts[0] = amounts[orderedTokens[0] == tokenAddresses[0] ? 0 : 1];
        tokensAmounts[1] = amounts[orderedTokens[1] == tokenAddresses[1] ? 1 : 0];

        for(uint256 i = 0; i < orderedTokens.length; i++) {
            if(orderedTokens[i] != _ethereumAddress) {
                _safeApprove(orderedTokens[i], liquidityPoolAddress, tokensAmounts[i]);
            }
        }

        if(orderedTokens[0] != _ethereumAddress && orderedTokens[1] != _ethereumAddress) {
            mooniswap.deposit(tokensAmounts, tokensAmounts);
        } else {
            mooniswap.deposit{value : orderedTokens[0] == _ethereumAddress ? tokensAmounts[0] : tokensAmounts[1]}(tokensAmounts, tokensAmounts);
        }

        _safeTransfer(liquidityPoolAddress, receiver, liquidityPoolAmount = IERC20(liquidityPoolAddress).balanceOf(address(this)));
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
        _safeTransfer(data.liquidityPoolAddress, data.receiver, liquidityPoolAmount = IERC20(data.liquidityPoolAddress).balanceOf(address(this)));
    }

    function _removeLiquidity(ProcessedLiquidityPoolData memory data) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {

        Mooniswap(data.liquidityPoolAddress).withdraw(liquidityPoolAmount = data.liquidityPoolAmount, new uint256[](2));

        tokensAmounts = new uint256[](data.tokensAmounts.length);
        for(uint256 i = 0; i < data.tokensAmounts.length; i++) {
            if(data.liquidityPoolTokens[i] != _ethereumAddress) {
                _safeTransfer(data.liquidityPoolTokens[i], data.receiver, data.tokensAmounts[i] = IERC20(data.liquidityPoolTokens[i]).balanceOf(address(this)));
            } else {
                (bool result,) = data.receiver.call{value:tokensAmounts[i] = address(this).balance}("");
                require(result, "ETH transfer failed");
            }
        }
    }

    function _swapLiquidity(ProcessedSwapData memory data) internal override virtual returns(uint256 outputAmount) {
        outputAmount = data.amount;
        for(uint256 i = 0; i < data.liquidityPoolAddresses.length; i++) {
            address inputToken = i == 0 ? data.inputToken : data.path[i - 1];
            if(inputToken != _ethereumAddress) {
                _safeApprove(inputToken, data.liquidityPoolAddresses[i], outputAmount);
            }
            if(inputToken == _ethereumAddress) {
                outputAmount = Mooniswap(data.liquidityPoolAddresses[i]).swap{value : outputAmount}(inputToken, data.path[i], outputAmount, 0, address(0));
            } else {
                outputAmount = Mooniswap(data.liquidityPoolAddresses[i]).swap(inputToken, data.path[i], outputAmount, 0, address(0));
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