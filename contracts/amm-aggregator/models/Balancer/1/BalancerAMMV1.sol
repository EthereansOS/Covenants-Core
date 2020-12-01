//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./IBalancerAMMV1.sol";
import "../../../common/AMM.sol";

contract BalancerAMMV1 is IBalancerAMMV1, AMM {

    address private immutable _wethAddress;

    constructor(address wethAddressInput) {
        _wethAddress = wethAddressInput;
    }

    function wethAddress() public override view returns(address) {
        return _wethAddress;
    }

    function info() public virtual override pure returns(string memory name, uint256 version) {
        return ("BalancerAMM", 1);
    }

    function addLiquidity(LiquidityProviderData memory data) public payable virtual override {
        _transferToMeAndCheckAllowance(data, data.liquidityProviderAddress, true);
        _addLiquidityWork(data, false);
        _flushBack(msg.sender, data.tokens, data.tokens.length);
    }

    function addLiquidityBatch(LiquidityProviderData[] memory data) public payable virtual override {
        (address[] memory tokens, uint256 tokensLength) = _transferToMeAndCheckAllowance(data, address(0), true);
        for(uint256 i = 0; i < data.length; i++) {
            _addLiquidityWork(data[i], true);
        }
        _flushBack(msg.sender, tokens, tokensLength);
    }

    function _addLiquidityWork(LiquidityProviderData memory data, bool checkAllowance) internal virtual {
        require(data.receiver != address(0), "Receiver cannot be void address");
        for(uint256 i = 0; i < data.tokens.length; i++) {
            if(data.tokens[i] == address(0) || checkAllowance) {
                if(data.tokens[i] == address(0)) {
                    IWETH(_wethAddress).deposit{value : data.amounts[i]}();
                }
                _checkAllowance(data.tokens[i] == address(0) ? _wethAddress : data.tokens[i], data.amounts[i], data.liquidityProviderAddress);
            }
        }
        BPool(data.liquidityProviderAddress).joinPool(data.liquidityProviderAmount, data.amounts);
        _safeTransfer(data.liquidityProviderAddress, data.receiver, data.liquidityProviderAmount);
    }

    function removeLiquidity(LiquidityProviderData memory data) public virtual override {
        _removeLiquidityWork(data);
        _flushBack(msg.sender, data.liquidityProviderAddress);
    }

    function removeLiquidityBatch(LiquidityProviderData[] memory data) public virtual override {
        for(uint256 i = 0; i < data.length; i++) {
            _removeLiquidityWork(data[i]);
        }
    }

    function _removeLiquidityWork(LiquidityProviderData memory data) internal virtual {
        require(data.receiver != address(0), "Receiver cannot be void address");
        BPool(data.liquidityProviderAddress).exitPool(data.liquidityProviderAmount, data.amounts);
        _flushBack(payable(data.receiver), data.tokens, data.tokens.length);
    }

    function swapLiquidity(LiquidityToSwap memory data) public payable virtual override {
        _transferToMeAndCheckAllowance(data.tokens[0], data.amount, address(0));
        _swapLiquidityWork(data);
        _flushBack(msg.sender, data.tokens, data.tokens.length);
    }

    function swapLiquidityBatch(LiquidityToSwap[] memory data) public payable virtual override {
        (address[] memory tokens, uint256 tokensLength) = _transferToMeAndCheckAllowance(data, address(0));
        for(uint256 i = 0; i < data.length; i++) {
            _swapLiquidityWork(data[i]);
        }
        _flushBack(msg.sender, tokens, tokensLength);
    }

    function _swapLiquidityWork(LiquidityToSwap memory data) internal virtual {
        require(data.receiver != address(0), "Receiver cannot be void address");
        if(data.enterInETH) {
            IWETH(_wethAddress).deposit{value : data.amount}();
        }
        (uint256 result, ) = BPool(data.liquidityProviderAddress).swapExactAmountIn(data.enterInETH ? _wethAddress : data.tokens[0], data.amount, data.tokens[1], 1, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        if(data.exitInETH) {
            IWETH(_wethAddress).withdraw(result);
        }
        _flushBack(payable(data.receiver), data.exitInETH ? address(0) : data.tokens[1]);
    }
}