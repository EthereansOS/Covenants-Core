//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./IUniswapV2AMMV1.sol";
import "../../../common/AMM.sol";

contract UniswapV2AMMV1 is IUniswapV2AMMV1, AMM {

    address private immutable _uniswapV2RouterAddress;

    address private immutable _wethAddress;

    address private immutable _factoryAddress;

    constructor(address uniswapV2RouterAddress) {
        _wethAddress = IUniswapV2Router(_uniswapV2RouterAddress = uniswapV2RouterAddress).WETH();
        _factoryAddress = IUniswapV2Router(uniswapV2RouterAddress).factory();
    }

    function router() public virtual override view returns(address) {
        return _uniswapV2RouterAddress;
    }

    function wethAddress() public virtual override view returns(address) {
        return _wethAddress;
    }

    function ethereumAddress() public view override(IAMM, AMM) returns(address) {
        return _wethAddress;
    }

    function info() public virtual override pure returns(string memory name, uint256 version) {
        return ("UniswapV2AMM", 1);
    }

    function addLiquidity(LiquidityPoolData memory data) public payable virtual override returns(uint256 liquidityPoolAmount, uint256[] memory tokenAmounts) {
        _transferToMeAndCheckAllowance(data, _uniswapV2RouterAddress, true);
        (liquidityPoolAmount, tokenAmounts) = _addLiquidityWork(data);
        _flushBack(msg.sender, data.tokens, data.tokens.length);
    }

    function addLiquidityBatch(LiquidityPoolData[] memory data) public payable virtual override returns(uint256[] memory liquidityPoolAmounts, uint256[][] memory tokensAmounts) {
        (address[] memory liquidityPoolTokens, uint256 tokensLength) = _transferToMeAndCheckAllowance(data, _uniswapV2RouterAddress, true);
        liquidityPoolAmounts = new uint256[](data.length);
        tokensAmounts = new uint256[][](data.length);
        for(uint256 i = 0; i < data.length; i++) {
            (liquidityPoolAmounts[i], tokensAmounts[i]) = _addLiquidityWork(data[i]);
        }
        _flushBack(msg.sender, liquidityPoolTokens, tokensLength);
    }

    function _addLiquidityWork(LiquidityPoolData memory data) internal virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokenAmounts) {
        require(data.receiver != address(0), "Receiver cannot be void address");
        uint256 tokenAAmount;
        uint256 tokenBAmount;
        if(data.tokens[0] != address(0) && data.tokens[1] != address(0)) {
            (tokenAAmount, tokenBAmount, liquidityPoolAmount) = IUniswapV2Router(_uniswapV2RouterAddress).addLiquidity(
                data.tokens[0],
                data.tokens[1],
                data.amounts[0],
                data.amounts[1],
                1,
                1,
                data.receiver,
                block.timestamp + 10000
            );
        } else {
            address token = data.tokens[0] != address(0) ? data.tokens[0] : data.tokens[1];
            uint256 amountTokenDesired = data.tokens[0] != address(0) ? data.amounts[0] : data.amounts[1];
            uint256 amountETHDesired = data.tokens[0] == address(0) ? data.amounts[0] : data.amounts[1];
            (tokenAAmount, tokenBAmount, liquidityPoolAmount) = IUniswapV2Router(_uniswapV2RouterAddress).addLiquidityETH {value : amountETHDesired} (
                token,
                amountTokenDesired,
                1,
                1,
                data.receiver,
                block.timestamp + 10000
            );
        }
        tokenAmounts = new uint256[](2);
        tokenAmounts[0] = tokenAAmount;
        tokenAmounts[1] = tokenBAmount;
    }

    function removeLiquidity(LiquidityPoolData memory data) public virtual override returns(uint256[] memory tokenAmounts) {
        _transferToMeAndCheckAllowance(data, _uniswapV2RouterAddress, false);
        tokenAmounts = _removeLiquidityWork(data);
        _flushBack(msg.sender, data.liquidityPoolAddress);
    }

    function removeLiquidityBatch(LiquidityPoolData[] memory data) public virtual override returns(uint256[][] memory tokensAmounts) {
        (address[] memory liquidityPoolTokens, uint256 tokensLength) = _transferToMeAndCheckAllowance(data, _uniswapV2RouterAddress, false);
        tokensAmounts = new uint256[][](data.length);
        for(uint256 i = 0; i < data.length; i++) {
            tokensAmounts[i] = _removeLiquidityWork(data[i]);
        }
        _flushBack(msg.sender, liquidityPoolTokens, tokensLength);
    }

    function _removeLiquidityWork(LiquidityPoolData memory data) internal virtual returns(uint256[] memory tokenAmounts) {
        require(data.receiver != address(0), "Receiver cannot be void address");
        address token0 = IUniswapV2Pair(data.liquidityPoolAddress).token0();
        address token1 = IUniswapV2Pair(data.liquidityPoolAddress).token1();
        tokenAmounts = new uint256[](2);
        if(data.tokens[0] != address(0) && data.tokens[1] != address(0)) {
            (uint256 amount0, uint256 amount1) = IUniswapV2Router(_uniswapV2RouterAddress).removeLiquidity(token0, token1, data.liquidityPoolAmount, 1, 1, data.receiver, block.timestamp + 1000);
            tokenAmounts[0] = data.tokens[0] == token0 ? amount0 : amount1;
            tokenAmounts[1] = data.tokens[1] == token1 ? amount1 : amount0;
        } else {
            (uint256 amount0, uint256 amountETH) = IUniswapV2Router(_uniswapV2RouterAddress).removeLiquidityETH(token0 != _wethAddress ? token0 : token1, data.liquidityPoolAmount, 1, 1, data.receiver, block.timestamp + 1000);
            tokenAmounts[0] = data.tokens[0] == address(0) ? amountETH : amount0;
            tokenAmounts[1] = data.tokens[1] == address(0) ? amountETH : amount0;
        }
    }

    function swapLiquidity(LiquidityToSwap memory data) public payable virtual override returns(uint256 result) {
        _transferToMeAndCheckAllowance(data.inputToken, data.amount, msg.sender, _uniswapV2RouterAddress);
        result = _swapLiquidityWork(data);
        _flushBack(msg.sender, data.enterInETH ? address(0) : data.inputToken);
    }

    function _swapLiquidityWork(LiquidityToSwap memory data) internal virtual returns(uint256) {
        require(data.receiver != address(0), "Receiver cannot be void address");
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

    function tokens(address liquidityPoolAddress) public override view returns(address[] memory tkns) {
        tkns = new address[](2);
        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress);
        tkns[0] = pair.token0();
        tkns[1] = pair.token1();
    }

    function liquidityPool(address[] memory liquidityPoolTokens) public override view returns(address) {
        return IUniswapV2Factory(_factoryAddress).getPair(liquidityPoolTokens[0] == address(0) ? _wethAddress : liquidityPoolTokens[0], liquidityPoolTokens[1] == address(0) ? _wethAddress : liquidityPoolTokens[1]);
    }

    function amounts(address liquidityPoolAddress) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokenAmounts) {
        tokenAmounts = new uint256[](2);
        liquidityPoolAmount = IUniswapV2Pair(liquidityPoolAddress).totalSupply();
        (uint256 amountA, uint256 amountB,) = IUniswapV2Pair(liquidityPoolAddress).getReserves();
        tokenAmounts[0] = amountA;
        tokenAmounts[1] = amountB;
    }

    function inPercentage(address liquidityPoolAddress, uint256 numerator, uint256 denominator, uint256 normalizeToDecimals) public view override(IAMM, AMM) returns (uint256 providerAmount, uint256[] memory tokenAmounts) {
        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress);

        providerAmount = (pair.totalSupply() * numerator) / denominator;
        (uint256 amount0, uint256 amount1, ) = pair.getReserves();

        tokenAmounts = new uint256[](2);
        tokenAmounts[0] = (amount0 * numerator) / denominator;
        tokenAmounts[1] = (amount1 * numerator) / denominator;

        if(normalizeToDecimals != 0) {
            tokenAmounts = _normalizeTokenAmountsToTheseDecimals(tokens(liquidityPoolAddress), tokenAmounts, normalizeToDecimals);
        }
    }

    function byLiquidityPoolAmount(address liquidityPoolAddress, uint256 liquidityPoolAmount, uint256 normalizeToDecimals) public view override(IAMM, AMM) returns(uint256[] memory tokenAmounts) {
        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress);

        uint256 numerator = liquidityPoolAmount != 0 ? liquidityPoolAmount : pair.balanceOf(msg.sender);
        uint256 denominator = pair.totalSupply();

        (uint256 amount0, uint256 amount1, ) = pair.getReserves();

        tokenAmounts = new uint256[](2);
        tokenAmounts[0] = (amount0 * numerator) / denominator;
        tokenAmounts[1] = (amount1 * numerator) / denominator;

        if(normalizeToDecimals != 0) {
            tokenAmounts = _normalizeTokenAmountsToTheseDecimals(tokens(liquidityPoolAddress), tokenAmounts, normalizeToDecimals);
        }
    }
}