//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AMM.sol";

import { IERC20Full } from "@ethereansos/swissknife/contracts/lib/GeneralUtilities.sol";

interface IWETH is IERC20Full {
    function deposit() external payable;

    function withdraw(uint256) external;
}

interface BPool is IERC20Full {

    function isPublicSwap()
        external view
        returns (bool);

    function isFinalized()
        external view
        returns (bool);

    function isBound(address t)
        external view
        returns (bool);

    function getNumTokens()
        external view
        returns (uint);

    function getCurrentTokens()
        external view
        returns (address[] memory tokens);

    function getFinalTokens()
        external view
        returns (address[] memory tokens);

    function getDenormalizedWeight(address token)
        external view
        returns (uint);

    function getTotalDenormalizedWeight()
        external view
        returns (uint);

    function getNormalizedWeight(address token)
        external view
        returns (uint);

    function getBalance(address token)
        external view
        returns (uint);

    function getSwapFee()
        external view
        returns (uint);

    function getController()
        external view
        returns (address);

    function calcOutGivenIn(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint tokenAmountIn,
        uint swapFee
    )
        external pure
        returns (uint tokenAmountOut);

    function calcInGivenOut(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint tokenAmountOut,
        uint swapFee
    )
        external pure
        returns (uint tokenAmountIn);

    function setSwapFee(uint swapFee)
        external;

    function setController(address manager)
        external;

    function setPublicSwap(bool public_)
        external;

    function finalize()
        external;

    function bind(address token, uint balance, uint denorm)
        external;

    function rebind(address token, uint balance, uint denorm)
        external;

    function unbind(address token)
        external;

    function gulp(address token)
        external;

    function getSpotPrice(address tokenIn, address tokenOut)
        external view
        returns (uint spotPrice);

    function getSpotPriceSansFee(address tokenIn, address tokenOut)
        external view
        returns (uint spotPrice);

    function joinPool(uint poolAmountOut, uint[] memory maxAmountsIn)
        external;

    function exitPool(uint poolAmountIn, uint[] memory minAmountsOut)
        external;

    function swapExactAmountIn(
        address tokenIn,
        uint tokenAmountIn,
        address tokenOut,
        uint minAmountOut,
        uint maxPrice
    )
        external
        returns (uint tokenAmountOut, uint spotPriceAfter);

    function swapExactAmountOut(
        address tokenIn,
        uint maxAmountIn,
        address tokenOut,
        uint tokenAmountOut,
        uint maxPrice
    )
        external
        returns (uint tokenAmountIn, uint spotPriceAfter);

    function joinswapExternAmountIn(address tokenIn, uint tokenAmountIn, uint minPoolAmountOut)
        external
        returns (uint poolAmountOut);

    function joinswapPoolAmountOut(address tokenIn, uint poolAmountOut, uint maxAmountIn)
        external
        returns (uint tokenAmountIn);

    function exitswapPoolAmountIn(address tokenOut, uint poolAmountIn, uint minAmountOut)
        external
        returns (uint tokenAmountOut);

    function exitswapExternAmountOut(address tokenOut, uint tokenAmountOut, uint maxPoolAmountIn)
        external
        returns (uint poolAmountIn);
}

contract BalancerAMMV1 is AMM {
    using AddressUtilities for address;
    using TransferUtilities for address;

    uint256 private constant BONE = 10**18;

    constructor(address wethAddressInput) AMM("Balancer", 1, wethAddressInput, 0, false) {
    }

    function _getLiquidityPoolCreationOperator(address[] memory, uint256[] memory, bool, bytes memory) internal virtual view override returns(address) {
        return address(0);
    }

    function _getLiquidityPoolOperator(uint256, address[] memory, bytes memory) internal override virtual view returns(address) {
        return address(0);
    }

    function _getSwapOperator(uint256, address[] memory, bytes memory) internal override virtual view returns(address) {
        return address(0);
    }

    function checkByTokensAdditionalData(address[] calldata tokens, bytes calldata additionalData) external override view {}
    function checkAddLiquidityEnsuringPoolAdditionalData(LiquidityPoolCreationParams[] calldata liquidityPoolCreationParams) external override view {}
    function _checkAddLiquidityAdditionalData(ProcessedLiquidityPoolParams[] memory) internal override view {}
    function _checkRemoveLiquidityAdditionalData(ProcessedLiquidityPoolParams[] memory) internal override view {}
    function _checkSwapAdditionalData(ProcessedSwapParams[] memory) internal override view {}

    function byLiquidityPool(uint256 liquidityPoolId) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory tokenAddresses) {

        address liquidityPoolAddress = _toAddress(liquidityPoolId);

        BPool pool = BPool(liquidityPoolAddress);

        liquidityPoolAmount = IWETH(liquidityPoolAddress).totalSupply();

        tokenAddresses = pool.getFinalTokens();

        tokensAmounts = new uint256[](tokenAddresses.length);
        for(uint256 i = 0; i < tokensAmounts.length; i++) {
            tokensAmounts[i] = pool.getBalance(tokenAddresses[i]);
        }
    }

    function _calculatePercentage(uint256 amount, uint256 numerator, uint256 denominator) internal virtual pure override returns(uint256) {
        return _bmul(_bdiv(numerator, denominator), amount);
    }

    function byLiquidityPoolAmount(uint256 liquidityPoolId, uint256 liquidityPoolAmount) view public virtual override returns(uint256[] memory tokensAmounts, address[] memory liquidityPoolTokens) {

        uint256 numerator = liquidityPoolAmount;
        uint256 denominator;

        (denominator, tokensAmounts, liquidityPoolTokens) = byLiquidityPool(liquidityPoolId);

        for(uint256 i = 0; i < tokensAmounts.length; i++) {
            tokensAmounts[i] = _bmul(_bdiv(numerator, denominator), tokensAmounts[i]);
        }
    }

    function byTokens(address[] memory, bytes calldata) public override view returns(uint256, uint256[] memory, uint256, address[] memory) {
    }

    function _getSwapOutput(uint256 value, uint256[] memory liquidityPoolIds, address[] memory path) view internal override returns(uint256) {
        address[] memory liquidityPoolAddresses = _toAddresses(liquidityPoolIds);
        uint256[] memory values = new uint256[](path.length);
        values[0] = value;
        for(uint256 i = 1 ; i < values.length; i++) {
            address tokenIn = path[i - 1] == address(0) ? _ethereumAddress : path[i - 1];
            address tokenOut = path[i] == address(0) ? _ethereumAddress : path[i];
            address liquidityPoolAddress = liquidityPoolAddresses[i - 1];
            BPool bPool = BPool(liquidityPoolAddress);
            values[i] = bPool.calcOutGivenIn(
                IWETH(tokenIn).balanceOf(liquidityPoolAddress),
                bPool.getNormalizedWeight(tokenIn),
                IWETH(tokenOut).balanceOf(liquidityPoolAddress),
                bPool.getNormalizedWeight(tokenOut),
                values[i - 1],
                bPool.getSwapFee()
            );
        }
        return values[values.length - 1];
    }

    function _getSwapInput(uint256 value, uint256[] memory liquidityPoolIds, address[] memory path) view internal override returns(uint256) {
        address[] memory liquidityPoolAddresses = _toAddresses(liquidityPoolIds);
        uint256[] memory values = new uint256[](path.length);
        values[values.length - 1] = value;
        for(uint256 i = values.length - 2 ; i >= 0; i--) {
            address tokenIn = path[i] == address(0) ? _ethereumAddress : path[i];
            address tokenOut = path[i + 1] == address(0) ? _ethereumAddress : path[i + 1];
            address liquidityPoolAddress = liquidityPoolAddresses[i];
            BPool bPool = BPool(liquidityPoolAddress);
            values[i] = bPool.calcInGivenOut(
                IWETH(tokenIn).balanceOf(liquidityPoolAddress),
                bPool.getNormalizedWeight(tokenIn),
                IWETH(tokenOut).balanceOf(liquidityPoolAddress),
                bPool.getNormalizedWeight(tokenOut),
                values[i + 1],
                bPool.getSwapFee()
            );
        }
        return values[0];
    }

    function _createLiquidityPoolAndAddLiquidity(LiquidityPoolCreationParams memory) internal virtual override returns(uint256, uint256[] memory, uint256, address[] memory) {
        revert("Balancer");
    }

    function _addLiquidity(ProcessedLiquidityPoolParams memory params) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId) {
        address liquidityPoolAddress = _toAddress(liquidityPoolId = params.liquidityPoolId);
        address ethereumAddress = _ethereumAddress;
        for(uint256 i = 0; i < params.liquidityPoolTokens.length; i++) {
            if(params.involvingETH && params.liquidityPoolTokens[i] == ethereumAddress) {
                IWETH(ethereumAddress).deposit{value : params.tokensAmounts[i]}();
            }
            params.liquidityPoolTokens[i].safeApprove(liquidityPoolAddress, params.tokensAmounts[i]);
        }
        BPool(liquidityPoolAddress).joinPool(liquidityPoolAmount = params.liquidityPoolAmount, tokensAmounts = params.tokensAmounts);
        if(params.receiver != address(this)) {
            liquidityPoolAddress.safeTransfer(params.receiver, liquidityPoolAmount);
        }
    }

    function _removeLiquidity(ProcessedLiquidityPoolParams memory params) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {
        tokensAmounts = _balanceOf(params.liquidityPoolTokens);
        BPool(_toAddress(params.liquidityPoolId)).exitPool(liquidityPoolAmount = params.liquidityPoolAmount, params.tokensAmounts);
        for(uint256 i = 0; i < params.tokensAmounts.length; i++) {
            tokensAmounts[i] -= params.liquidityPoolTokens[i].balanceOf(address(this));
        }
        if(params.receiver == address(this)) {
            return (liquidityPoolAmount, tokensAmounts);
        }
        address ethereumAddress = _ethereumAddress;
        for(uint256 i = 0; i < params.tokensAmounts.length; i++) {
            bool eth = params.involvingETH && params.liquidityPoolTokens[i] == ethereumAddress;
            if(eth) {
                IWETH(ethereumAddress).withdraw(tokensAmounts[i]);
            }
            (eth ? address(0) : params.liquidityPoolTokens[i]).safeTransfer(params.receiver, tokensAmounts[i]);
        }
    }

    function _swap(ProcessedSwapParams memory params) internal override virtual returns(uint256 outputAmount) {
        address[] memory liquidityPoolAddresses = _toAddresses(params.liquidityPoolIds);
        address ethereumAddress = _ethereumAddress;
        if(params.enterInETH) {
            IWETH(ethereumAddress).deposit{value : params.amount}();
        }
        outputAmount = params.amount;
        for(uint256 i = 0; i < liquidityPoolAddresses.length; i++) {
            address inputToken = i == 0 ? params.enterInETH ? ethereumAddress : params.inputToken : params.path[i - 1];
            inputToken.safeApprove(liquidityPoolAddresses[i], outputAmount);
            address outputToken = i != liquidityPoolAddresses.length - 1 || !params.exitInETH ? params.path[i] : ethereumAddress;
            (outputAmount, ) = BPool(liquidityPoolAddresses[i]).swapExactAmountIn(inputToken, outputAmount, outputToken, i == liquidityPoolAddresses.length - 1 ? params.minAmount : 0, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        }
        if(params.exitInETH) {
            IWETH(ethereumAddress).withdraw(outputAmount);
        }
        if(params.receiver != address(this)) {
            params.path[params.path.length - 1].safeTransfer(params.receiver, outputAmount);
        }
    }

    function addLiquidity(LiquidityPoolParams memory params) payable public virtual override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId, address[] memory liquidityPoolTokens) {
        return _addLiquidity(params, !_delegateMode());
    }

    function _addLiquidity(LiquidityPoolParams memory params, bool flushBack) private returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId, address[] memory liquidityPoolTokens) {
        ProcessedLiquidityPoolParams memory processedLiquidityPoolParams = _processLiquidityPoolParams(params);
        _transferToMeAndApprove(liquidityPoolTokens = processedLiquidityPoolParams.liquidityPoolTokens, processedLiquidityPoolParams.tokensAmounts, processedLiquidityPoolParams.liquidityPoolOperator, params.involvingETH);
        (liquidityPoolAmount, tokensAmounts, liquidityPoolId) = _addLiquidity(processedLiquidityPoolParams);
        _flushBack(liquidityPoolTokens, flushBack, true);
    }

    function _flushBack(address token, bool flushBack) private {
        if(!flushBack) {
            return;
        }
        token.safeTransfer(msg.sender, token.balanceOf(address(this)));
    }

    function _flushBack(address[] memory tokens, bool flushBack, bool alsoETH) private {
        if(!flushBack) {
            return;
        }
        for(uint256 i = 0; i < tokens.length; i++) {
            tokens[i].safeTransfer(msg.sender, tokens[i].balanceOf(address(this)));
        }
        if(alsoETH) {
            _flushBack(address(0), flushBack);
        }
    }

    function _flushBack(address[][] memory tokens, bool flushBack) private {
        if(!flushBack) {
            return;
        }
        for(uint256 i = 0; i < tokens.length; i++) {
            _flushBack(tokens[i], flushBack, false);
        }
        _flushBack(address(0), flushBack);
    }

    function addLiquidityBatch(LiquidityPoolParams[] memory params) payable public virtual override returns(uint256[] memory liquidityPoolAmounts, uint256[][] memory tokensAmounts, uint256[] memory liquidityPoolIds, address[][] memory liquidityPoolTokens) {
        liquidityPoolAmounts = new uint256[](params.length);
        tokensAmounts = new uint256[][](params.length);
        liquidityPoolIds = new uint256[](params.length);
        liquidityPoolTokens = new address[][](params.length);
        for(uint256 i = 0; i < params.length; i++) {
            (liquidityPoolAmounts[i], tokensAmounts[i], liquidityPoolIds[i], liquidityPoolTokens[i]) = _addLiquidity(params[i], false);
        }
        _flushBack(liquidityPoolTokens, !_delegateMode());
    }

    function removeLiquidityBatch(LiquidityPoolParams[] memory params) public virtual override returns(uint256[] memory liquidityPoolAmounts, uint256[][] memory tokensAmounts, address[][] memory liquidityPoolTokens) {
        liquidityPoolAmounts = new uint256[](params.length);
        tokensAmounts = new uint256[][](params.length);
        liquidityPoolTokens = new address[][](params.length);
        for(uint256 i = 0; i < params.length; i++) {
            (liquidityPoolAmounts[i], tokensAmounts[i], liquidityPoolTokens[i]) = removeLiquidity(params[i]);
        }
    }

    function swapBatch(SwapParams[] memory params) payable public virtual override returns(uint256[] memory outputAmounts) {
        outputAmounts = new uint256[](params.length);
        for(uint256 i = 0; i < params.length; i++) {
            outputAmounts[i] = swap(params[i]);
        }
    }

    function _bmul(uint a, uint b)
        internal pure
        returns (uint)
    {
        uint c0 = a * b;
        require(a == 0 || c0 / a == b, "ERR_MUL_OVERFLOW");
        uint c1 = c0 + (BONE / 2);
        require(c1 >= c0, "ERR_MUL_OVERFLOW");
        uint c2 = c1 / BONE;
        return c2;
    }

    function _bdiv(uint a, uint b)
        internal pure
        returns (uint)
    {
        require(b != 0, "ERR_DIV_ZERO");
        uint c0 = a * BONE;
        require(a == 0 || c0 / a == BONE, "ERR_DIV_INTERNAL"); // _bmul overflow
        uint c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL"); //  badd require
        uint c2 = c1 / b;
        return c2;
    }
}