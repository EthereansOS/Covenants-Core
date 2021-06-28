//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./ISushiSwapAMMV1.sol";
import "../../../common/AMM.sol";

contract SushiSwapAMMV1 is ISushiSwapAMMV1, AMM {

    address private _sushiSwapV2RouterAddress;

    address private _wethAddress;

    constructor(address sushiSwapV2RouterAddress) AMM("SushiSwap", 1, _wethAddress = IUniswapV2Router(_sushiSwapV2RouterAddress = sushiSwapV2RouterAddress).WETH(), 2, true) {
    }


    function factory() private view returns (address) {
        return IUniswapV2Router(_sushiSwapV2RouterAddress).factory();
    }

    function sushiSwapData() public virtual override view returns(address routerAddress, address wethAddress) {
        routerAddress = _sushiSwapV2RouterAddress;
        wethAddress = _wethAddress;
    }

    function byLiquidityPool(address liquidityPoolAddress) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory tokenAddresses) {

        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress);

        address token0 = pair.token0();
        address token1 = pair.token1();
        if(IUniswapV2Factory(factory()).getPair(token0, token1) != liquidityPoolAddress) {
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

        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress = IUniswapV2Factory(factory()).getPair(tokenAddresses[0], tokenAddresses[1]));

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
        return IUniswapV2Router(_sushiSwapV2RouterAddress).getAmountsOut(tokenAmount, realPath);
    }

    function _getLiquidityPoolOperator(address, address[] memory) internal override virtual view returns(address) {
        return _sushiSwapV2RouterAddress;
    }

    function _getLiquidityPoolCreator(address[] memory, uint256[] memory, bool) internal virtual view override returns(address) {
        return _sushiSwapV2RouterAddress;
    }

    function _createLiquidityPoolAndAddLiquidity(address[] memory tokenAddresses, uint256[] memory amounts, bool involvingETH, address, address receiver) internal virtual override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address liquidityPoolAddress, address[] memory orderedTokens) {
        tokensAmounts = new uint256[](2);
        orderedTokens = new address[](2);
        if(!involvingETH) {
            (tokensAmounts[0], tokensAmounts[1], liquidityPoolAmount) = IUniswapV2Router(_sushiSwapV2RouterAddress).addLiquidity(
                tokenAddresses[0],
                tokenAddresses[1],
                amounts[0],
                amounts[1],
                1,
                1,
                receiver,
                block.timestamp + 10000
            );
        } else {
            address token = tokenAddresses[0] != _wethAddress ? tokenAddresses[0] : tokenAddresses[1];
            uint256 amountTokenDesired = tokenAddresses[0] != _wethAddress ? amounts[0] : amounts[1];
            uint256 amountETHDesired = tokenAddresses[0] == _wethAddress ? amounts[0] : amounts[1];
            (tokensAmounts[0], tokensAmounts[1], liquidityPoolAmount) = IUniswapV2Router(_sushiSwapV2RouterAddress).addLiquidityETH {value : amountETHDesired} (
                token,
                amountTokenDesired,
                1,
                1,
                receiver,
                block.timestamp + 10000
            );
        }
        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress = IUniswapV2Factory(factory()).getPair(tokenAddresses[0], tokenAddresses[1]));
        orderedTokens[0] = pair.token0();
        orderedTokens[1] = pair.token1();
    }

    function _addLiquidity(ProcessedLiquidityPoolData memory processedLiquidityPoolData) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {
        tokensAmounts = new uint256[](2);
        if(!processedLiquidityPoolData.involvingETH) {
            (tokensAmounts[0], tokensAmounts[1], liquidityPoolAmount) = IUniswapV2Router(_sushiSwapV2RouterAddress).addLiquidity(
                processedLiquidityPoolData.liquidityPoolTokens[0],
                processedLiquidityPoolData.liquidityPoolTokens[1],
                processedLiquidityPoolData.tokensAmounts[0],
                processedLiquidityPoolData.tokensAmounts[1],
                1,
                1,
                processedLiquidityPoolData.receiver,
                block.timestamp + 10000
            );
        } else {
            address token = processedLiquidityPoolData.liquidityPoolTokens[0] != _wethAddress ? processedLiquidityPoolData.liquidityPoolTokens[0] : processedLiquidityPoolData.liquidityPoolTokens[1];
            uint256 amountTokenDesired = processedLiquidityPoolData.liquidityPoolTokens[0] != _wethAddress ? processedLiquidityPoolData.tokensAmounts[0] : processedLiquidityPoolData.tokensAmounts[1];
            uint256 amountETHDesired = processedLiquidityPoolData.liquidityPoolTokens[0] == _wethAddress ? processedLiquidityPoolData.tokensAmounts[0] : processedLiquidityPoolData.tokensAmounts[1];
            (tokensAmounts[0], tokensAmounts[1], liquidityPoolAmount) = IUniswapV2Router(_sushiSwapV2RouterAddress).addLiquidityETH {value : amountETHDesired} (
                token,
                amountTokenDesired,
                1,
                1,
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
            (amount0, amount1) = IUniswapV2Router(_sushiSwapV2RouterAddress).removeLiquidity(processedLiquidityPoolData.liquidityPoolTokens[0], processedLiquidityPoolData.liquidityPoolTokens[1], processedLiquidityPoolData.liquidityPoolAmount, 1, 1, processedLiquidityPoolData.receiver, block.timestamp + 1000);
        } else {
            (amount0, amount1) = IUniswapV2Router(_sushiSwapV2RouterAddress).removeLiquidityETH(processedLiquidityPoolData.liquidityPoolTokens[0] != _wethAddress ? processedLiquidityPoolData.liquidityPoolTokens[0] : processedLiquidityPoolData.liquidityPoolTokens[1], processedLiquidityPoolData.liquidityPoolAmount, 1, 1, processedLiquidityPoolData.receiver, block.timestamp + 1000);
        }
        tokensAmounts[0] = amount0;
        tokensAmounts[1] = amount1;
    }

    function _swapLiquidity(ProcessedSwapData memory data) internal override virtual returns(uint256 outputAmount) {
        address[] memory path = new address[](data.path.length + 1);
        path[0] = data.enterInETH ? _wethAddress : data.inputToken;
        for(uint256 i = 0; i < data.path.length; i++) {
            path[i + 1] = data.path[i];
        }
        if(data.exitInETH) {
            path[path.length - 1] = _wethAddress;
        }
        if(!data.enterInETH && !data.exitInETH) {
            return IUniswapV2Router(_sushiSwapV2RouterAddress).swapExactTokensForTokens(data.amount, 1, path, data.receiver, block.timestamp + 1000)[path.length - 1];
        }
        if(data.enterInETH) {
            return IUniswapV2Router(_sushiSwapV2RouterAddress).swapExactETHForTokens{value : data.amount}(1, path, data.receiver, block.timestamp + 1000)[path.length - 1];
        }
        if(data.exitInETH) {
            return IUniswapV2Router(_sushiSwapV2RouterAddress).swapExactTokensForETH(data.amount, 1, path, data.receiver, block.timestamp + 1000)[path.length - 1];
        }
        return 0;
    }
}