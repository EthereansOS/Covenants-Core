//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

interface IUniswapV3Pool {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
    function tickSpacing() external view returns (int24);
    function maxLiquidityPerTick() external view returns (uint128);
    function liquidity() external view returns (uint128);
}
