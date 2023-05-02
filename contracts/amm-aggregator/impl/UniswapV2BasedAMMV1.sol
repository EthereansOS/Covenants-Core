//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AMM.sol";

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair is IERC20Full {
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

    address private _routerAddress;
    address private _factoryAddress;

    constructor(string memory name, uint256 version, address routerAddress) AMM(name, version, IUniswapV2Router(routerAddress).WETH(), 2, true, 20, address(0)) {
        _factoryAddress = IUniswapV2Router(_routerAddress = routerAddress).factory();
    }

    function byLiquidityPool(uint256 liquidityPoolId) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory tokenAddresses) {

        address liquidityPoolAddress = _toAddress(liquidityPoolId);

        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress);

        address token0 = pair.token0();
        address token1 = pair.token1();
        if(IUniswapV2Factory(_factoryAddress).getPair(token0, token1) != liquidityPoolAddress) {
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

    function byTokens(address[] memory tokenAddresses, bytes calldata) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId, address[] memory orderedTokens) {

        address liquidityPoolAddress = IUniswapV2Factory(_factoryAddress).getPair(tokenAddresses[0], tokenAddresses[1]);
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

    function _getSwapOutput(uint256 value, uint256[] memory, address[] memory path) view internal override returns(uint256) {
        uint256[] memory values = IUniswapV2Router(_routerAddress).getAmountsOut(value, path);
        return values[values.length - 1];
    }

    function _getSwapInput(uint256 value, uint256[] memory, address[] memory path) view internal override returns(uint256) {
        uint256[] memory values = IUniswapV2Router(_routerAddress).getAmountsIn(value, _reverse(path));
        return values[values.length - 1];
    }

    function _getLiquidityPoolOperator(uint256, address[] memory, bytes memory) internal override virtual view returns(address) {
        return _routerAddress;
    }

    function _getLiquidityPoolCreationOperator(address[] memory, uint256[] memory, bool, bytes memory) internal virtual view override returns(address) {
        return _routerAddress;
    }

    function _getSwapOperator(uint256, address[] memory, bytes memory) internal override virtual view returns(address) {
        return _routerAddress;
    }

    function checkByTokensAdditionalData(address[] calldata tokens, bytes calldata additionalData) external override view {}
    function checkAddLiquidityEnsuringPoolAdditionalData(LiquidityPoolCreationParams[] calldata liquidityPoolCreationParams) external override view {}
    function _checkAddLiquidityAdditionalData(ProcessedLiquidityPoolParams[] memory) internal override view {}
    function _checkRemoveLiquidityAdditionalData(ProcessedLiquidityPoolParams[] memory) internal override view {}
    function _checkSwapAdditionalData(ProcessedSwapParams[] memory) internal override view {}

    function _createLiquidityPoolAndAddLiquidity(LiquidityPoolCreationParams memory liquidityPoolCreationData) internal override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId, address[] memory orderedTokens) {
        tokensAmounts = new uint256[](2);
        orderedTokens = new address[](2);
        if(!liquidityPoolCreationData.involvingETH) {
            (tokensAmounts[0], tokensAmounts[1], liquidityPoolAmount) = IUniswapV2Router(_routerAddress).addLiquidity(
                liquidityPoolCreationData.tokenAddresses[0],
                liquidityPoolCreationData.tokenAddresses[1],
                liquidityPoolCreationData.amounts[0],
                liquidityPoolCreationData.amounts[1],
                liquidityPoolCreationData.minAmounts[0],
                liquidityPoolCreationData.minAmounts[1],
                liquidityPoolCreationData.receiver,
                liquidityPoolCreationData.deadline
            );
        } else {
            uint256 tokenIndex = liquidityPoolCreationData.tokenAddresses[0] != _ethereumAddress ? 0 : 1;
            (tokensAmounts[tokenIndex], tokensAmounts[1 - tokenIndex], liquidityPoolAmount) = IUniswapV2Router(_routerAddress).addLiquidityETH {value : liquidityPoolCreationData.amounts[1 - tokenIndex]} (
                liquidityPoolCreationData.tokenAddresses[tokenIndex],
                liquidityPoolCreationData.amounts[tokenIndex],
                liquidityPoolCreationData.minAmounts[tokenIndex],
                liquidityPoolCreationData.minAmounts[1 - tokenIndex],
                liquidityPoolCreationData.receiver,
                liquidityPoolCreationData.deadline
            );
        }
        address liquidityPoolAddress = IUniswapV2Factory(_factoryAddress).getPair(liquidityPoolCreationData.tokenAddresses[0], liquidityPoolCreationData.tokenAddresses[1]);
        liquidityPoolId = _toNumber(liquidityPoolAddress);
        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress);
        orderedTokens[0] = pair.token0();
        orderedTokens[1] = pair.token1();
    }

    function _addLiquidity(ProcessedLiquidityPoolParams memory processedLiquidityPoolParams) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId) {
        tokensAmounts = new uint256[](2);
        if(!processedLiquidityPoolParams.involvingETH) {
            (tokensAmounts[0], tokensAmounts[1], liquidityPoolAmount) = IUniswapV2Router(_routerAddress).addLiquidity(
                processedLiquidityPoolParams.liquidityPoolTokens[0],
                processedLiquidityPoolParams.liquidityPoolTokens[1],
                processedLiquidityPoolParams.tokensAmounts[0],
                processedLiquidityPoolParams.tokensAmounts[1],
                processedLiquidityPoolParams.minAmounts[0],
                processedLiquidityPoolParams.minAmounts[1],
                processedLiquidityPoolParams.receiver,
                processedLiquidityPoolParams.deadline
            );
        } else {
            uint256 tokenIndex = processedLiquidityPoolParams.liquidityPoolTokens[0] != _ethereumAddress ? 0 : 1;
            address token = processedLiquidityPoolParams.liquidityPoolTokens[tokenIndex];
            uint256 amountTokenDesired = processedLiquidityPoolParams.tokensAmounts[tokenIndex];
            uint256 amountETHDesired = processedLiquidityPoolParams.tokensAmounts[1 - tokenIndex];
            (tokensAmounts[tokenIndex], tokensAmounts[1 - tokenIndex], liquidityPoolAmount) = IUniswapV2Router(_routerAddress).addLiquidityETH {value : amountETHDesired} (
                token,
                amountTokenDesired,
                processedLiquidityPoolParams.minAmounts[tokenIndex],
                processedLiquidityPoolParams.minAmounts[1 - tokenIndex],
                processedLiquidityPoolParams.receiver,
                processedLiquidityPoolParams.deadline
            );
        }
        address liquidityPoolAddress = IUniswapV2Factory(_factoryAddress).getPair(processedLiquidityPoolParams.liquidityPoolTokens[0], processedLiquidityPoolParams.liquidityPoolTokens[1]);
        liquidityPoolId = _toNumber(liquidityPoolAddress);
    }

    function _removeLiquidity(ProcessedLiquidityPoolParams memory processedLiquidityPoolParams) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {

        liquidityPoolAmount = processedLiquidityPoolParams.liquidityPoolAmount;

        tokensAmounts = new uint256[](2);
        if(!processedLiquidityPoolParams.involvingETH) {
            (tokensAmounts[0], tokensAmounts[1]) = IUniswapV2Router(_routerAddress).removeLiquidity(processedLiquidityPoolParams.liquidityPoolTokens[0], processedLiquidityPoolParams.liquidityPoolTokens[1], processedLiquidityPoolParams.liquidityPoolAmount, processedLiquidityPoolParams.minAmounts[0], processedLiquidityPoolParams.minAmounts[1], processedLiquidityPoolParams.receiver, processedLiquidityPoolParams.deadline);
        } else {
            uint256 tokenIndex = processedLiquidityPoolParams.liquidityPoolTokens[0] != _ethereumAddress ? 0 : 1;
            (tokensAmounts[tokenIndex], tokensAmounts[1 - tokenIndex]) = IUniswapV2Router(_routerAddress).removeLiquidityETH(processedLiquidityPoolParams.liquidityPoolTokens[tokenIndex], processedLiquidityPoolParams.liquidityPoolAmount, processedLiquidityPoolParams.minAmounts[tokenIndex], processedLiquidityPoolParams.minAmounts[1 - tokenIndex], processedLiquidityPoolParams.receiver, processedLiquidityPoolParams.deadline);
        }
    }

    function _swap(ProcessedSwapParams memory data) internal override virtual returns(uint256 outputAmount) {
        address[] memory path = new address[](data.path.length + 1);
        path[0] = data.enterInETH ? _ethereumAddress : data.inputToken;
        for(uint256 i = 0; i < data.path.length; i++) {
            path[i + 1] = data.path[i];
        }
        if(data.exitInETH) {
            path[path.length - 1] = _ethereumAddress;
        }
        if(!data.enterInETH && !data.exitInETH) {
            return IUniswapV2Router(_routerAddress).swapExactTokensForTokens(data.amount, data.minAmount, path, data.receiver, data.deadline)[path.length - 1];
        }
        if(data.enterInETH) {
            return IUniswapV2Router(_routerAddress).swapExactETHForTokens{value : data.amount}(data.minAmount, path, data.receiver, data.deadline)[path.length - 1];
        }
        if(data.exitInETH) {
            return IUniswapV2Router(_routerAddress).swapExactTokensForETH(data.amount, data.minAmount, path, data.receiver, data.deadline)[path.length - 1];
        }
        return 0;
    }
}