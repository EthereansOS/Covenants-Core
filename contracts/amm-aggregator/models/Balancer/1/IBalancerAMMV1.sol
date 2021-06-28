//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "../../../common/IAMM.sol";
import "../../../util/IERC20.sol";

interface IBalancerAMMV1 is IAMM {
}

interface IWETH {
    function deposit() external payable;

    function withdraw(uint wad) external;

    function totalSupply() external view returns (uint);

    function approve(address guy, uint wad) external returns (bool);

    function transfer(address dst, uint wad) external returns (bool);

    function transferFrom(address src, address dst, uint wad)
        external
        returns (bool);
}

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