//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./LiquidityMiningData.sol";

interface IFarmMath {

    /* OPERATIONS:
     * 0: Toggle Setup - Active and terminated setup
     * 1: Toggle Setup - Re-active new pinned setup
     * 2: Disable Setup
     * 3: Edit RewardPerBlock in free non-pinned setup
     * 4: Open new Position
     * 5: Add liquidity
     * 6: Withdraw position
     * 7: Unlock position
     */
    function calculateGiveAndTransfer(LiquidityMiningSetup memory setup, uint256 setupIndex, bool hasPinned, uint256 pinnedIndex, uint256 operation, bytes memory data) external view returns(LiquidityMiningSetup memory newSetup, uint256 toGive, uint256 toTransfer);
}