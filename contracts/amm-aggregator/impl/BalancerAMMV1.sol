//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AMM.sol";
import "../../util/IWETH.sol";

interface BPool {

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

    function joinPool(uint poolAmountOut, uint[] calldata maxAmountsIn)
        external;

    function exitPool(uint poolAmountIn, uint[] calldata minAmountsOut)
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

    uint public constant BONE = 10**18;

    bool private _multi;

    constructor(address wethAddressInput) AMM("Balancer", 1, wethAddressInput, 0, false) {
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

    function calculatePercentage(uint256 amount, uint256 numerator, uint256 denominator) internal virtual pure override returns(uint256) {
        return bmul(bdiv(numerator, denominator), amount);
    }

    function byLiquidityPoolAmount(address liquidityPoolAddress, uint256 liquidityPoolAmount) view public virtual override returns(uint256[] memory tokensAmounts, address[] memory liquidityPoolTokens) {

        uint256 numerator = liquidityPoolAmount;
        uint256 denominator;

        (denominator, tokensAmounts, liquidityPoolTokens) = byLiquidityPool(liquidityPoolAddress);

        for(uint256 i = 0; i < tokensAmounts.length; i++) {
            tokensAmounts[i] = bmul(bdiv(numerator, denominator), tokensAmounts[i]);
        }
    }

    function byTokens(address[] memory) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address liquidityPoolAddress, address[] memory orderedTokens) {
        return (liquidityPoolAmount, tokensAmounts, liquidityPoolAddress, orderedTokens);
    }

    function _getSwapOutput(uint256 value, address[] calldata liquidityPoolAddresses, address[] calldata path) view internal override returns(uint256[] memory values) {
        values = new uint256[](path.length);
        values[0] = value;
        for(uint256 i = 1 ; i < values.length; i++) {
            address tokenIn = path[i - 1] == address(0) ? _ethereumAddress : path[i - 1];
            address tokenOut = path[i] == address(0) ? _ethereumAddress : path[i];
            address liquidityPoolAddress = liquidityPoolAddresses[i - 1];
            BPool bPool = BPool(liquidityPoolAddress);
            values[i] = bPool.calcOutGivenIn(
                IERC20(tokenIn).balanceOf(liquidityPoolAddress),
                bPool.getNormalizedWeight(tokenIn),
                IERC20(tokenOut).balanceOf(liquidityPoolAddress),
                bPool.getNormalizedWeight(tokenOut),
                values[i - 1],
                bPool.getSwapFee()
            );
        }
    }

    function _getSwapInput(uint256 value, address[] calldata liquidityPoolAddresses, address[] calldata path) view internal override returns(uint256[] memory values) {
        values = new uint256[](path.length);
        values[values.length - 1] = value;
        for(uint256 i = values.length - 2 ; i >= 0; i--) {
            address tokenIn = path[i] == address(0) ? _ethereumAddress : path[i];
            address tokenOut = path[i + 1] == address(0) ? _ethereumAddress : path[i + 1];
            address liquidityPoolAddress = liquidityPoolAddresses[i];
            BPool bPool = BPool(liquidityPoolAddress);
            values[i] = bPool.calcInGivenOut(
                IERC20(tokenIn).balanceOf(liquidityPoolAddress),
                bPool.getNormalizedWeight(tokenIn),
                IERC20(tokenOut).balanceOf(liquidityPoolAddress),
                bPool.getNormalizedWeight(tokenOut),
                values[i + 1],
                bPool.getSwapFee()
            );
        }
    }

    function _getLiquidityPoolCreator(address[] memory, uint256[] memory, bool) internal virtual view override returns(address) {
        return address(0);
    }

    function _createLiquidityPoolAndAddLiquidity(address[] memory, uint256[] memory, bool, address, address, uint256[] memory) internal virtual override returns(uint256, uint256[] memory, address, address[] memory) {
        revert("Balancer");
    }

    function _addLiquidity(ProcessedLiquidityPoolData memory data) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {
        for(uint256 i = 0; i < data.liquidityPoolTokens.length; i++) {
            if(data.involvingETH && data.liquidityPoolTokens[i] == _ethereumAddress) {
                IWETH(_ethereumAddress).deposit{value : data.tokensAmounts[i]}();
            }
            _safeApprove(data.liquidityPoolTokens[i], data.liquidityPoolAddress, data.tokensAmounts[i]);
        }
        BPool(data.liquidityPoolAddress).joinPool(liquidityPoolAmount = data.liquidityPoolAmount, tokensAmounts = data.tokensAmounts);
        _safeTransfer(data.liquidityPoolAddress, data.receiver, liquidityPoolAmount);
    }

    function _removeLiquidity(ProcessedLiquidityPoolData memory data) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {
        BPool(data.liquidityPoolAddress).exitPool(liquidityPoolAmount = data.liquidityPoolAmount, data.tokensAmounts);
        tokensAmounts = new uint256[](data.tokensAmounts.length);
        for(uint256 i = 0; i < data.tokensAmounts.length; i++) {
            bool eth = data.involvingETH && data.liquidityPoolTokens[i] == _ethereumAddress;
            if(!eth) {
                _safeTransfer(data.liquidityPoolTokens[i], data.receiver, data.tokensAmounts[i] = IERC20(data.liquidityPoolTokens[i]).balanceOf(address(this)));
            } else {
                if(!_multi) {
                    IWETH(_ethereumAddress).withdraw(tokensAmounts[i] = IERC20(_ethereumAddress).balanceOf(address(this)));
                    (bool result,) = data.receiver.call{value: tokensAmounts[i]}("");
                    require(result, "ETH transfer failed");
                }
            }
        }
    }

    function _swapLiquidity(ProcessedSwapData memory data) internal override virtual returns(uint256 outputAmount) {
        if(data.enterInETH) {
            IWETH(_ethereumAddress).deposit{value : data.amount}();
        }
        outputAmount = data.amount;
        for(uint256 i = 0; i < data.liquidityPoolAddresses.length; i++) {
            address inputToken = i == 0 ? data.enterInETH ? _ethereumAddress : data.inputToken : data.path[i - 1];
            _safeApprove(inputToken, data.liquidityPoolAddresses[i], outputAmount);
            address outputToken = i != data.liquidityPoolAddresses.length - 1 || !data.exitInETH ? data.path[i] : _ethereumAddress;
            (outputAmount, ) = BPool(data.liquidityPoolAddresses[i]).swapExactAmountIn(inputToken, outputAmount, outputToken, data.minAmount, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        }
        if(data.exitInETH) {
            IWETH(_ethereumAddress).withdraw(outputAmount);
            (bool result,) = data.receiver.call{value:outputAmount}("");
            require(result, "ETH transfer failed");
        } else {
            _safeTransfer(data.path[data.path.length - 1], data.receiver, outputAmount);
        }
    }

    function addLiquidity(LiquidityPoolData memory data) payable public virtual override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory liquidityPoolTokens) {
        ProcessedLiquidityPoolData memory processedLiquidityPoolData = _processLiquidityPoolData(data);
        _transferToMeAndCheckAllowance(liquidityPoolTokens = processedLiquidityPoolData.liquidityPoolTokens, processedLiquidityPoolData.tokensAmounts, processedLiquidityPoolData.liquidityPoolOperator, data.involvingETH);
        (liquidityPoolAmount, tokensAmounts) = _addLiquidity(processedLiquidityPoolData);
        if(!_multi) {
            _flushBack(liquidityPoolTokens);
        }
    }

    function addLiquidityBatch(LiquidityPoolData[] memory data) payable public virtual override returns(uint256[] memory liquidityPoolAmounts, uint256[][] memory tokensAmounts, address[][] memory liquidityPoolTokens) {
        liquidityPoolAmounts = new uint256[](data.length);
        tokensAmounts = new uint256[][](data.length);
        liquidityPoolTokens = new address[][](data.length);
        _multi = true;
        for(uint256 i = 0; i < data.length; i++) {
            (liquidityPoolAmounts[i], tokensAmounts[i], liquidityPoolTokens[i]) = addLiquidity(data[i]);
        }
        for(uint256 i = 0; i < data.length; i++) {
            _flushBack(liquidityPoolTokens[i]);
        }
        _flushBack(address(0));
        _multi = false;
    }

    function removeLiquidityBatch(LiquidityPoolData[] memory data) public virtual override returns(uint256[] memory liquidityPoolAmounts, uint256[][] memory tokensAmounts, address[][] memory liquidityPoolTokens) {
        liquidityPoolAmounts = new uint256[](data.length);
        tokensAmounts = new uint256[][](data.length);
        liquidityPoolTokens = new address[][](data.length);
        _multi = true;
        for(uint256 i = 0; i < data.length; i++) {
            (liquidityPoolAmounts[i], tokensAmounts[i], liquidityPoolTokens[i]) = removeLiquidity(data[i]);
        }
        for(uint256 i = 0; i < data.length; i++) {
            _flushBack(liquidityPoolTokens[i]);
        }
        _flushBack(address(0));
        _multi = false;
    }

    function swapLiquidityBatch(SwapData[] memory data) payable public virtual override returns(uint256[] memory outputAmounts) {
        outputAmounts = new uint256[](data.length);
        _multi = true;
        for(uint256 i = 0; i < data.length; i++) {
            outputAmounts[i] = swapLiquidity(data[i]);
        }
        _multi = false;
    }

    function bmul(uint a, uint b)
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

    function bdiv(uint a, uint b)
        internal pure
        returns (uint)
    {
        require(b != 0, "ERR_DIV_ZERO");
        uint c0 = a * BONE;
        require(a == 0 || c0 / a == BONE, "ERR_DIV_INTERNAL"); // bmul overflow
        uint c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL"); //  badd require
        uint c2 = c1 / b;
        return c2;
    }
}