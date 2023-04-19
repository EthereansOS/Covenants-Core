//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AMM.sol";
import "../../util/uniswapV2/IUniswapV2Router.sol";
import "../../util/uniswapV2/IUniswapV2Pair.sol";
import "../../util/uniswapV2/IUniswapV2Factory.sol";

contract UniswapV2BasedAMMV1 is AMM {

    address public immutable routerAddress;
    address public immutable factoryAddress;

    constructor(string memory name, uint256 version, address _routerAddress) AMM(name, version, IUniswapV2Router(_routerAddress).WETH(), 2, true) {
        factoryAddress = IUniswapV2Router(routerAddress = _routerAddress).factory();
    }

    function byLiquidityPool(address liquidityPoolAddress) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory tokenAddresses) {

        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress);

        address token0 = pair.token0();
        address token1 = pair.token1();
        if(IUniswapV2Factory(factoryAddress).getPair(token0, token1) != liquidityPoolAddress) {
            return(0, new uint256[](0), new address[](0));
        }

        liquidityPoolAmount = pair.totalSupply();

        tokensAmounts = new uint256[](2);
        (uint256 amountA, uint256 amountB,) = pair.getReserves();
        tokensAmounts[0] = amountA;
        tokensAmounts[1] = amountB;

        tokenAddresses = new address[](2);
        tokenAddresses[0] = token0;
        tokenAddresses[1] = token1;
    }

    function byTokens(address[] memory tokenAddresses) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address liquidityPoolAddress, address[] memory orderedTokens) {

        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress = IUniswapV2Factory(factoryAddress).getPair(tokenAddresses[0], tokenAddresses[1]));

        if(address(pair) == address(0)) {
            return (liquidityPoolAmount, tokensAmounts, liquidityPoolAddress, orderedTokens);
        }

        liquidityPoolAmount = pair.totalSupply();

        tokensAmounts = new uint256[](2);
        (uint256 amountA, uint256 amountB,) = pair.getReserves();
        tokensAmounts[0] = amountA;
        tokensAmounts[1] = amountB;

        orderedTokens = new address[](2);
        orderedTokens[0] = pair.token0();
        orderedTokens[1] = pair.token1();
    }

    function getSwapOutput(address tokenAddress, uint256 tokenAmount, address[] calldata, address[] calldata path) view public virtual override returns(uint256[] memory) {
        address[] memory realPath = new address[](path.length + 1);
        realPath[0] = tokenAddress;
        for(uint256 i = 0; i < path.length; i++) {
            realPath[i + 1] = path[i];
        }
        return IUniswapV2Router(routerAddress).getAmountsOut(tokenAmount, realPath);
    }

    function _getLiquidityPoolOperator(address, address[] memory) internal override virtual view returns(address) {
        return routerAddress;
    }

    function _getLiquidityPoolCreator(address[] memory, uint256[] memory, bool) internal virtual view override returns(address) {
        return routerAddress;
    }

    function _createLiquidityPoolAndAddLiquidity(address[] memory tokenAddresses, uint256[] memory amounts, bool involvingETH, address, address receiver, uint256[] memory minAmounts) internal virtual override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address liquidityPoolAddress, address[] memory orderedTokens) {
        tokensAmounts = new uint256[](2);
        orderedTokens = new address[](2);
        if(!involvingETH) {
            (tokensAmounts[0], tokensAmounts[1], liquidityPoolAmount) = IUniswapV2Router(routerAddress).addLiquidity(
                tokenAddresses[0],
                tokenAddresses[1],
                amounts[0],
                amounts[1],
                minAmounts[0],
                minAmounts[1],
                receiver,
                block.timestamp + 10000
            );
        } else {
            uint256 tokenIndex = tokenAddresses[0] != _ethereumAddress ? 0 : 1;
            address token = tokenAddresses[tokenIndex];
            uint256 amountTokenDesired = amounts[tokenIndex];
            uint256 amountETHDesired = amounts[1 - tokenIndex];
            (tokensAmounts[0], tokensAmounts[1], liquidityPoolAmount) = IUniswapV2Router(routerAddress).addLiquidityETH {value : amountETHDesired} (
                token,
                amountTokenDesired,
                minAmounts[tokenIndex],
                minAmounts[1 - tokenIndex],
                receiver,
                block.timestamp + 10000
            );
        }
        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress = IUniswapV2Factory(factoryAddress).getPair(tokenAddresses[0], tokenAddresses[1]));
        orderedTokens[0] = pair.token0();
        orderedTokens[1] = pair.token1();
    }

    function _addLiquidity(ProcessedLiquidityPoolData memory processedLiquidityPoolData) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {
        tokensAmounts = new uint256[](2);
        if(!processedLiquidityPoolData.involvingETH) {
            (tokensAmounts[0], tokensAmounts[1], liquidityPoolAmount) = IUniswapV2Router(routerAddress).addLiquidity(
                processedLiquidityPoolData.liquidityPoolTokens[0],
                processedLiquidityPoolData.liquidityPoolTokens[1],
                processedLiquidityPoolData.tokensAmounts[0],
                processedLiquidityPoolData.tokensAmounts[1],
                processedLiquidityPoolData.minAmounts[0],
                processedLiquidityPoolData.minAmounts[1],
                processedLiquidityPoolData.receiver,
                block.timestamp + 10000
            );
        } else {
            uint256 tokenIndex = processedLiquidityPoolData.liquidityPoolTokens[0] != _ethereumAddress ? 0 : 1;
            address token = processedLiquidityPoolData.liquidityPoolTokens[tokenIndex];
            uint256 amountTokenDesired = processedLiquidityPoolData.tokensAmounts[tokenIndex];
            uint256 amountETHDesired = processedLiquidityPoolData.tokensAmounts[1 - tokenIndex];
            (tokensAmounts[0], tokensAmounts[1], liquidityPoolAmount) = IUniswapV2Router(routerAddress).addLiquidityETH {value : amountETHDesired} (
                token,
                amountTokenDesired,
                processedLiquidityPoolData.minAmounts[tokenIndex],
                processedLiquidityPoolData.minAmounts[1 - tokenIndex],
                processedLiquidityPoolData.receiver,
                block.timestamp + 10000
            );
        }
    }

    function _removeLiquidity(ProcessedLiquidityPoolData memory processedLiquidityPoolData) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {

        liquidityPoolAmount = processedLiquidityPoolData.liquidityPoolAmount;

        tokensAmounts = new uint256[](2);
        uint256 amount0;
        uint256 amount1;
        if(!processedLiquidityPoolData.involvingETH) {
            (amount0, amount1) = IUniswapV2Router(routerAddress).removeLiquidity(processedLiquidityPoolData.liquidityPoolTokens[0], processedLiquidityPoolData.liquidityPoolTokens[1], processedLiquidityPoolData.liquidityPoolAmount, 1, 1, processedLiquidityPoolData.receiver, block.timestamp + 1000);
        } else {
            (amount0, amount1) = IUniswapV2Router(routerAddress).removeLiquidityETH(processedLiquidityPoolData.liquidityPoolTokens[0] != _ethereumAddress ? processedLiquidityPoolData.liquidityPoolTokens[0] : processedLiquidityPoolData.liquidityPoolTokens[1], processedLiquidityPoolData.liquidityPoolAmount, 1, 1, processedLiquidityPoolData.receiver, block.timestamp + 1000);
        }
        tokensAmounts[0] = amount0;
        tokensAmounts[1] = amount1;
    }

    function _swapLiquidity(ProcessedSwapData memory data) internal override virtual returns(uint256 outputAmount) {
        address[] memory path = new address[](data.path.length + 1);
        path[0] = data.enterInETH ? _ethereumAddress : data.inputToken;
        for(uint256 i = 0; i < data.path.length; i++) {
            path[i + 1] = data.path[i];
        }
        if(data.exitInETH) {
            path[path.length - 1] = _ethereumAddress;
        }
        if(!data.enterInETH && !data.exitInETH) {
            return IUniswapV2Router(routerAddress).swapExactTokensForTokens(data.amount, 1, path, data.receiver, block.timestamp + 1000)[path.length - 1];
        }
        if(data.enterInETH) {
            return IUniswapV2Router(routerAddress).swapExactETHForTokens{value : data.amount}(1, path, data.receiver, block.timestamp + 1000)[path.length - 1];
        }
        if(data.exitInETH) {
            return IUniswapV2Router(routerAddress).swapExactTokensForETH(data.amount, 1, path, data.receiver, block.timestamp + 1000)[path.length - 1];
        }
        return 0;
    }
}