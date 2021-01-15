//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./IUniswapV2AMMV1.sol";
import "../../../common/AMM.sol";

contract UniswapV2AMMV1 is IUniswapV2AMMV1, AMM {

    address private _uniswapV2RouterAddress;

    address private _wethAddress;

    address private immutable _factoryAddress;

    constructor(address uniswapV2RouterAddress) AMM(_wethAddress = IUniswapV2Router(_uniswapV2RouterAddress = uniswapV2RouterAddress).WETH()) {
        _factoryAddress = IUniswapV2Router(uniswapV2RouterAddress).factory();
    }

    function uniswapData() public virtual override view returns(address routerAddress, address factoryAddress, address wethAddress) {
        routerAddress = _uniswapV2RouterAddress;
        factoryAddress = _factoryAddress;
        wethAddress = _wethAddress;
    }

    function info() public virtual override pure returns(string memory name, uint256 version) {
        return ("UniswapV2AMM", 1);
    }

    function byLiquidityPool(address liquidityPoolAddress) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokenAmounts, address[] memory tokenAddresses) {

        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress);

        liquidityPoolAmount = pair.totalSupply();

        tokenAmounts = new uint256[](2);
        (uint256 amountA, uint256 amountB,) = pair.getReserves();
        tokenAmounts[0] = amountA;
        tokenAmounts[1] = amountB;

        tokenAddresses = new address[](2);
        tokenAddresses[0] = pair.token0();
        tokenAddresses[1] = pair.token1();
    }

    function byTokens(address[] memory tokenAddresses) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokenAmounts, address liquidityPoolAddress) {

        require(tokenAddresses.length == 2, "Length must be 2");

        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress = IUniswapV2Factory(_factoryAddress).getPair(tokenAddresses[0], tokenAddresses[1]));

        liquidityPoolAmount = pair.totalSupply();

        tokenAmounts = new uint256[](2);
        (uint256 amountA, uint256 amountB,) = pair.getReserves();
        tokenAmounts[0] = amountA;
        tokenAmounts[1] = amountB;
    }

    function _getLiquidityPoolOperator(address,  address[] memory) internal override virtual view returns(address) {
        return _uniswapV2RouterAddress;
    }

    function _addLiquidity(ProcessedLiquidityPoolData memory processedLiquidityPoolData) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokenAmounts) {
        uint256 tokenAAmount;
        uint256 tokenBAmount;
        if(!processedLiquidityPoolData.ethIsInvolved) {
            (tokenAAmount, tokenBAmount, liquidityPoolAmount) = IUniswapV2Router(_uniswapV2RouterAddress).addLiquidity(
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
            (tokenAAmount, tokenBAmount, liquidityPoolAmount) = IUniswapV2Router(_uniswapV2RouterAddress).addLiquidityETH {value : amountETHDesired} (
                token,
                amountTokenDesired,
                1,
                1,
                processedLiquidityPoolData.receiver,
                block.timestamp + 10000
            );
        }
        tokenAmounts = new uint256[](2);
        tokenAmounts[0] = tokenAAmount;
        tokenAmounts[1] = tokenBAmount;
    }

    function _removeLiquidity(ProcessedLiquidityPoolData memory processedLiquidityPoolData) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokenAmounts) {

        liquidityPoolAmount = processedLiquidityPoolData.liquidityPoolAmount;

        tokenAmounts = new uint256[](2);
        uint256 amount0;
        uint256 amount1;
        if(!processedLiquidityPoolData.ethIsInvolved) {
            (amount0, amount1) = IUniswapV2Router(_uniswapV2RouterAddress).removeLiquidity(processedLiquidityPoolData.liquidityPoolTokens[0], processedLiquidityPoolData.liquidityPoolTokens[1], processedLiquidityPoolData.liquidityPoolAmount, 1, 1, processedLiquidityPoolData.receiver, block.timestamp + 1000);
        } else {
            (amount0, amount1) = IUniswapV2Router(_uniswapV2RouterAddress).removeLiquidityETH(processedLiquidityPoolData.liquidityPoolTokens[0] != _wethAddress ? processedLiquidityPoolData.liquidityPoolTokens[0] : processedLiquidityPoolData.liquidityPoolTokens[1], processedLiquidityPoolData.liquidityPoolAmount, 1, 1, processedLiquidityPoolData.receiver, block.timestamp + 1000);
        }
        tokenAmounts[0] = amount0;
        tokenAmounts[1] = amount1;
    }

    function _swapLiquidity(ProcessedSwapData memory data) internal override virtual returns(uint256 outputAmount) {
        address[] memory path = new address[](data.paths.length + 1);
        path[0] = data.enterInETH ? _wethAddress : data.inputToken;
        for(uint256 i = 0; i < data.paths.length; i++) {
            path[i + 1] = data.paths[i];
        }
        if(data.exitInETH) {
            path[path.length - 1] = _wethAddress;
        }
        if(!data.enterInETH && !data.exitInETH) {
            return IUniswapV2Router(_uniswapV2RouterAddress).swapExactTokensForTokens(data.amount, 1, path, data.receiver, block.timestamp + 1000)[path.length - 1];
        }
        if(data.enterInETH) {
            return IUniswapV2Router(_uniswapV2RouterAddress).swapExactETHForTokens{value : data.amount}(1, path, data.receiver, block.timestamp + 1000)[path.length - 1];
        }
        if(data.exitInETH) {
            return IUniswapV2Router(_uniswapV2RouterAddress).swapExactTokensForETH(data.amount, 1, path, data.receiver, block.timestamp + 1000)[path.length - 1];
        }
        return 0;
    }
}