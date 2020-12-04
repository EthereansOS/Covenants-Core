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

    function addLiquidity(LiquidityProviderData memory data) public payable virtual override {
        _transferToMeAndCheckAllowance(data, _uniswapV2RouterAddress, true);
        _addLiquidityWork(data);
        _flushBack(_sender(data), data.tokens, data.tokens.length);
    }

    function addLiquidityBatch(LiquidityProviderData[] memory data) public payable virtual override {
        (address[] memory tokens, uint256 tokensLength) = _transferToMeAndCheckAllowance(data, _uniswapV2RouterAddress, true);
        for(uint256 i = 0; i < data.length; i++) {
            _addLiquidityWork(data[i]);
        }
        _flushBack(_sender(data[0]), tokens, tokensLength);
    }

    function _addLiquidityWork(LiquidityProviderData memory data) internal virtual {
        require(data.receiver != address(0), "Receiver cannot be void address");
        if(data.tokens[0] != address(0) && data.tokens[1] != address(0)) {
            IUniswapV2Router(_uniswapV2RouterAddress).addLiquidity(
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
            IUniswapV2Router(_uniswapV2RouterAddress).addLiquidityETH {value : amountETHDesired} (
                token,
                amountTokenDesired,
                1,
                1,
                data.receiver,
                block.timestamp + 10000
            );
        }
    }

    function removeLiquidity(LiquidityProviderData memory data) public virtual override {
        _transferToMeAndCheckAllowance(data, _uniswapV2RouterAddress, false);
        _removeLiquidityWork(data);
        _flushBack(_sender(data), data.liquidityProviderAddress);
    }

    function removeLiquidityBatch(LiquidityProviderData[] memory data) public virtual override {
        (address[] memory tokens, uint256 tokensLength) = _transferToMeAndCheckAllowance(data, _uniswapV2RouterAddress, false);
        for(uint256 i = 0; i < data.length; i++) {
            _removeLiquidityWork(data[i]);
        }
        _flushBack(_sender(data[0]), tokens, tokensLength);
    }

    function _removeLiquidityWork(LiquidityProviderData memory data) internal virtual {
        require(data.receiver != address(0), "Receiver cannot be void address");
        address token0 = IUniswapV2Pair(data.liquidityProviderAddress).token0();
        address token1 = IUniswapV2Pair(data.liquidityProviderAddress).token1();
        if(data.tokens[0] != address(0) && data.tokens[1] != address(0)) {
            IUniswapV2Router(_uniswapV2RouterAddress).removeLiquidity(token0, token1, data.liquidityProviderAmount, 1, 1, data.receiver, block.timestamp + 1000);
        } else {
            IUniswapV2Router(_uniswapV2RouterAddress).removeLiquidityETH(token0 != _wethAddress ? token0 : token1, data.liquidityProviderAmount, 1, 1, data.receiver, block.timestamp + 1000);
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

    function tokens(address liquidityProviderAddress) public override view returns(address[] memory tkns) {
        tkns = new address[](2);
        IUniswapV2Pair pair = IUniswapV2Pair(liquidityProviderAddress);
        tkns[0] = pair.token0();
        tkns[1] = pair.token1();
    }

    function inPercentage(address liquidityProviderAddress, uint256 numerator, uint256 denominator, uint256 normalizeToDecimals) public view override(IAMM, AMM) returns (uint256 providerAmount, uint256[] memory tokenAmounts) {
        IUniswapV2Pair pair = IUniswapV2Pair(liquidityProviderAddress);

        providerAmount = (pair.totalSupply() * numerator) / denominator;
        (uint256 amount0, uint256 amount1, ) = pair.getReserves();

        tokenAmounts = new uint256[](2);
        tokenAmounts[0] = (amount0 * numerator) / denominator;
        tokenAmounts[1] = (amount1 * numerator) / denominator;

        if(normalizeToDecimals != 0) {
            tokenAmounts = _normalizeDecimals(tokens(liquidityProviderAddress), tokenAmounts, normalizeToDecimals);
        }
    }

    function byAmount(address liquidityProviderAddress, uint256 liquidityProviderAmount, uint256 normalizeToDecimals) public view override(IAMM, AMM) returns(uint256[] memory tokenAmounts) {
        IUniswapV2Pair pair = IUniswapV2Pair(liquidityProviderAddress);

        uint256 numerator = liquidityProviderAmount != 0 ? liquidityProviderAmount : pair.balanceOf(msg.sender);
        uint256 denominator = pair.totalSupply();

        (uint256 amount0, uint256 amount1, ) = pair.getReserves();

        tokenAmounts = new uint256[](2);
        tokenAmounts[0] = (amount0 * numerator) / denominator;
        tokenAmounts[1] = (amount1 * numerator) / denominator;

        if(normalizeToDecimals != 0) {
            tokenAmounts = _normalizeDecimals(tokens(liquidityProviderAddress), tokenAmounts, normalizeToDecimals);
        }
    }
}