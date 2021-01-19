//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./IBalancerAMMV1.sol";
import "../../../common/AMM.sol";

contract BalancerAMMV1 is IBalancerAMMV1, AMM {

    constructor(address wethAddressInput) AMM(wethAddressInput) {
    }

    function info() public virtual override pure returns(string memory name, uint256 version) {
        return ("BalancerAMM", 1);
    }

    function _getLiquidityPoolOperator(address, address[] memory) internal override virtual view returns(address) {
        return address(0);
    }

    function byLiquidityPool(address liquidityPoolAddress) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory tokenAddresses) {

        BPool pool = BPool(liquidityPoolAddress);

        liquidityPoolAmount = IERC20(liquidityPoolAddress).totalSupply();

        tokenAddresses = pool.getFinalTokens();

        tokensAmounts = new uint256[](tokenAddresses.length);
        for(uint256 i = 0; i < tokensAmounts.length; i++) {
            tokensAmounts[i] = pool.getBalance(tokenAddresses[i]);
        }
    }

    function byTokens(address[] memory) public override view returns(uint256, uint256[] memory, address, address[] memory) {
        revert("balancer");
    }

    function _addLiquidity(ProcessedLiquidityPoolData memory data) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {
        for(uint256 i = 0; i < data.liquidityPoolTokens.length; i++) {
            if(data.involvingETH && data.liquidityPoolTokens[i] == ethereumAddress) {
                IWETH(ethereumAddress).deposit{value : data.tokensAmounts[i]}();
                _safeApprove(ethereumAddress, data.liquidityPoolAddress, data.tokensAmounts[i]);
            } else {
                _safeApprove(data.liquidityPoolTokens[i], data.liquidityPoolAddress, data.tokensAmounts[i]);
            }
        }
        BPool(data.liquidityPoolAddress).joinPool(liquidityPoolAmount = data.liquidityPoolAmount, tokensAmounts = data.tokensAmounts);
        _safeTransfer(data.liquidityPoolAddress, data.receiver, liquidityPoolAmount);
    }

    function _removeLiquidity(ProcessedLiquidityPoolData memory data) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {
        BPool(data.liquidityPoolAddress).exitPool(liquidityPoolAmount = data.liquidityPoolAmount, data.tokensAmounts);
        tokensAmounts = new uint256[](data.tokensAmounts.length);
        for(uint256 i = 0; i < data.tokensAmounts.length; i++) {
            bool eth = data.involvingETH && data.liquidityPoolTokens[i] == ethereumAddress;
            if(!eth) {
                _safeTransfer(data.liquidityPoolTokens[i], data.receiver, data.tokensAmounts[i] = IERC20(data.liquidityPoolTokens[i]).balanceOf(address(this)));
            } else {
                IWETH(ethereumAddress).withdraw(tokensAmounts[i] = IERC20(ethereumAddress).balanceOf(address(this)));
                payable(data.receiver).transfer(tokensAmounts[i]);
            }
        }
    }

    function _swapLiquidity(ProcessedSwapData memory data) internal override virtual returns(uint256 outputAmount) {
        if(data.enterInETH) {
            IWETH(ethereumAddress).deposit{value : data.amount}();
        }
        outputAmount = data.amount;
        for(uint256 i = 0; i < data.liquidityPoolAddresses.length; i++) {
            address inputToken = i == 0 ? data.enterInETH ? ethereumAddress : data.inputToken : data.paths[i - 1];
            _safeApprove(inputToken, data.liquidityPoolAddresses[i], outputAmount);
            address outputToken = i != data.liquidityPoolAddresses.length - 1 || !data.exitInETH ? data.paths[i] : ethereumAddress;
            (outputAmount, ) = BPool(data.liquidityPoolAddresses[i]).swapExactAmountIn(inputToken, outputAmount, outputToken, 1, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        }
        if(data.exitInETH) {
            IWETH(ethereumAddress).withdraw(outputAmount);
            payable(data.receiver).transfer(outputAmount);
        } else {
            _safeTransfer(data.paths[data.paths.length - 1], data.receiver, outputAmount);
        }
    }
}