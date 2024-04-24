//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

interface ITickLens {
    struct PopulatedTick {
        int24 tick;
        int128 liquidityNet;
        uint128 liquidityGross;
    }

    function getPopulatedTicksInWord(address pool, int16 tickBitmapIndex)
        external
        view
        returns (PopulatedTick[] memory populatedTicks);
}
