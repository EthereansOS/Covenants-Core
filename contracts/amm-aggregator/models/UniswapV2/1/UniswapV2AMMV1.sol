//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

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

    function info() public virtual override pure returns(string memory name, uint256 version) {
        return ("UniswapV2AMM", 1);
    }

    function addLiquidity(LiquidityPoolData memory data) public payable virtual override returns(uint256 amount) {
        _transferToMeAndCheckAllowance(data, _uniswapV2RouterAddress, true);
        amount = _addLiquidityWork(data);
        _flushBack(_sender(data), data.tokens, data.tokens.length);
    }

    function addLiquidityBatch(LiquidityPoolData[] memory data) public payable virtual override returns(uint256[] memory amounts) {
        (address[] memory tokens, uint256 tokensLength) = _transferToMeAndCheckAllowance(data, _uniswapV2RouterAddress, true);
        amounts = new uint256[](data.length);
        for(uint256 i = 0; i < data.length; i++) {
            amounts[i] = _addLiquidityWork(data[i]);
        }
        _flushBack(_sender(data[0]), tokens, tokensLength);
    }

    function _addLiquidityWork(LiquidityPoolData memory data) internal virtual returns(uint256 amount) {
        require(data.receiver != address(0), "Receiver cannot be void address");
        if(data.tokens[0] != address(0) && data.tokens[1] != address(0)) {
            (,,amount) = IUniswapV2Router(_uniswapV2RouterAddress).addLiquidity(
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
            (,,amount) = IUniswapV2Router(_uniswapV2RouterAddress).addLiquidityETH {value : amountETHDesired} (
                token,
                amountTokenDesired,
                1,
                1,
                data.receiver,
                block.timestamp + 10000
            );
        }
    }

    function removeLiquidity(LiquidityPoolData memory data) public virtual override returns(uint256[] memory amounts) {
        _transferToMeAndCheckAllowance(data, _uniswapV2RouterAddress, false);
        amounts = _removeLiquidityWork(data);
        _flushBack(_sender(data), data.liquidityPoolAddress);
    }

    function removeLiquidityBatch(LiquidityPoolData[] memory data) public virtual override returns(uint256[][] memory amounts) {
        (address[] memory tokens, uint256 tokensLength) = _transferToMeAndCheckAllowance(data, _uniswapV2RouterAddress, false);
        amounts = new uint256[][](data.length);
        for(uint256 i = 0; i < data.length; i++) {
            amounts[i] = _removeLiquidityWork(data[i]);
        }
        _flushBack(_sender(data[0]), tokens, tokensLength);
    }

    function _removeLiquidityWork(LiquidityPoolData memory data) internal virtual returns(uint256[] memory amounts) {
        require(data.receiver != address(0), "Receiver cannot be void address");
        address token0 = IUniswapV2Pair(data.liquidityPoolAddress).token0();
        address token1 = IUniswapV2Pair(data.liquidityPoolAddress).token1();
        amounts = new uint256[](2);
        if(data.tokens[0] != address(0) && data.tokens[1] != address(0)) {
            (uint256 amount0, uint256 amount1) = IUniswapV2Router(_uniswapV2RouterAddress).removeLiquidity(token0, token1, data.liquidityPoolAmount, 1, 1, data.receiver, block.timestamp + 1000);
            amounts[0] = data.tokens[0] == token0 ? amount0 : amount1;
            amounts[1] = data.tokens[1] == token1 ? amount1 : amount0;
        } else {
            (uint256 amount0, uint256 amountETH) = IUniswapV2Router(_uniswapV2RouterAddress).removeLiquidityETH(token0 != _wethAddress ? token0 : token1, data.liquidityPoolAmount, 1, 1, data.receiver, block.timestamp + 1000);
            amounts[0] = data.tokens[0] == address(0) ? amountETH : amount0;
            amounts[1] = data.tokens[1] == address(0) ? amountETH : amount0;
        }
    }

    function swapLiquidity(LiquidityToSwap memory data) public payable virtual override {
        _transferToMeAndCheckAllowance(data.tokens[0], data.amount, _uniswapV2RouterAddress);
        _swapLiquidityWork(data);
        _flushBack(_sender(data), data.tokens, data.tokens.length);
    }

    function swapLiquidityBatch(LiquidityToSwap[] memory data) public payable virtual override {
        (address[] memory tokens, uint256 tokensLength) = _transferToMeAndCheckAllowance(data, _uniswapV2RouterAddress);
        for(uint256 i = 0; i < data.length; i++) {
            _swapLiquidityWork(data[i]);
        }
        _flushBack(_sender(data[0]), tokens, tokensLength);
    }

    function _swapLiquidityWork(LiquidityToSwap memory data) internal virtual {
        require(data.receiver != address(0), "Receiver cannot be void address");
        if(!data.enterInETH && !data.exitInETH) {
            IUniswapV2Router(_uniswapV2RouterAddress).swapExactTokensForTokens(data.amount, 1, data.tokens, data.receiver, block.timestamp + 1000);
            return;
        }
        if(data.enterInETH) {
            IUniswapV2Router(_uniswapV2RouterAddress).swapExactETHForTokens{value : data.amount}(1, data.tokens, data.receiver, block.timestamp + 1000);
            return;
        }
        if(data.exitInETH) {
            IUniswapV2Router(_uniswapV2RouterAddress).swapExactTokensForETH(data.amount, 1, data.tokens, data.receiver, block.timestamp + 1000);
            return;
        }
    }

    function tokens(address liquidityPoolAddress) public override view returns(address[] memory tkns) {
        tkns = new address[](2);
        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress);
        tkns[0] = pair.token0();
        tkns[1] = pair.token1();
    }

    function inPercentage(address liquidityPoolAddress, uint256 numerator, uint256 denominator, uint256 normalizeToDecimals) public view override(IAMM, AMM) returns (uint256 providerAmount, uint256[] memory tokenAmounts) {
        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress);

        providerAmount = (pair.totalSupply() * numerator) / denominator;
        (uint256 amount0, uint256 amount1, ) = pair.getReserves();

        tokenAmounts = new uint256[](2);
        tokenAmounts[0] = (amount0 * numerator) / denominator;
        tokenAmounts[1] = (amount1 * numerator) / denominator;

        if(normalizeToDecimals != 0) {
            tokenAmounts = _normalizeDecimals(tokens(liquidityPoolAddress), tokenAmounts, normalizeToDecimals);
        }
    }

    function byAmount(address liquidityPoolAddress, uint256 liquidityPoolAmount, uint256 normalizeToDecimals) public view override(IAMM, AMM) returns(uint256[] memory tokenAmounts) {
        IUniswapV2Pair pair = IUniswapV2Pair(liquidityPoolAddress);

        uint256 numerator = liquidityPoolAmount != 0 ? liquidityPoolAmount : pair.balanceOf(msg.sender);
        uint256 denominator = pair.totalSupply();

        (uint256 amount0, uint256 amount1, ) = pair.getReserves();

        tokenAmounts = new uint256[](2);
        tokenAmounts[0] = (amount0 * numerator) / denominator;
        tokenAmounts[1] = (amount1 * numerator) / denominator;

        if(normalizeToDecimals != 0) {
            tokenAmounts = _normalizeDecimals(tokens(liquidityPoolAddress), tokenAmounts, normalizeToDecimals);
        }
    }
}