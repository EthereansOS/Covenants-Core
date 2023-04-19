//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AMM.sol";
import "../../util/IERC20.sol";

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair is IERC20 {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function factory() external view returns(address);
}

interface IUniswapV2Router {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] memory path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] memory path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] memory path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] memory path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] memory path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] memory path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] memory path) external view returns (uint[] memory amounts);
}

contract UniswapV2BasedAMMV1 is AMM {

    address public immutable routerAddress;
    address public immutable factoryAddress;

    constructor(string memory name, uint256 version, address _routerAddress) AMM(name, version, IUniswapV2Router(_routerAddress).WETH(), 2, true) {
        factoryAddress = IUniswapV2Router(routerAddress = _routerAddress).factory();
    }

    function byLiquidityPool(uint256 liquidityPoolId) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory tokenAddresses) {

        address liquidityPoolAddress = _toAddress(liquidityPoolId);

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

    function byTokens(address[] memory tokenAddresses) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId, address[] memory orderedTokens) {

        address liquidityPoolAddress = IUniswapV2Factory(factoryAddress).getPair(tokenAddresses[0], tokenAddresses[1]);
        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress);

        if(address(pair) == address(0)) {
            return (liquidityPoolAmount, tokensAmounts, liquidityPoolId, orderedTokens);
        }

        liquidityPoolId = _toNumber(liquidityPoolAddress);

        liquidityPoolAmount = pair.totalSupply();

        tokensAmounts = new uint256[](2);
        (uint256 amountA, uint256 amountB,) = pair.getReserves();
        tokensAmounts[0] = amountA;
        tokensAmounts[1] = amountB;

        orderedTokens = new address[](2);
        orderedTokens[0] = pair.token0();
        orderedTokens[1] = pair.token1();
    }

    function _getSwapOutput(uint256 value, uint256[] memory, address[] memory path) view internal override returns(uint256[] memory) {
        return IUniswapV2Router(routerAddress).getAmountsOut(value, path);
    }

    function _getSwapInput(uint256 value, uint256[] memory, address[] memory path) view internal override returns(uint256[] memory) {
        return IUniswapV2Router(routerAddress).getAmountsIn(value, path);
    }

    function _getLiquidityPoolOperator(uint256, address[] memory) internal override virtual view returns(address) {
        return routerAddress;
    }

    function _getLiquidityPoolCreator(address[] memory, uint256[] memory, bool) internal virtual view override returns(address) {
        return routerAddress;
    }

    function _createLiquidityPoolAndAddLiquidity(address[] memory tokenAddresses, uint256[] memory amounts, bool involvingETH, address, address receiver, uint256[] memory minAmounts) internal override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId, address[] memory orderedTokens) {
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
            (tokensAmounts[0], tokensAmounts[1], liquidityPoolAmount) = IUniswapV2Router(routerAddress).addLiquidityETH {value : amounts[1 - tokenIndex]} (
                tokenAddresses[tokenIndex],
                amounts[tokenIndex],
                minAmounts[tokenIndex],
                minAmounts[1 - tokenIndex],
                receiver,
                block.timestamp + 10000
            );
        }
        address liquidityPoolAddress = IUniswapV2Factory(factoryAddress).getPair(tokenAddresses[0], tokenAddresses[1]);
        liquidityPoolId = _toNumber(liquidityPoolAddress);
        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress);
        orderedTokens[0] = pair.token0();
        orderedTokens[1] = pair.token1();
    }

    function _addLiquidity(ProcessedLiquidityPoolData memory processedLiquidityPoolData) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId) {
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
        address liquidityPoolAddress = IUniswapV2Factory(factoryAddress).getPair(processedLiquidityPoolData.liquidityPoolTokens[0], processedLiquidityPoolData.liquidityPoolTokens[1]);
        liquidityPoolId = _toNumber(liquidityPoolAddress);
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