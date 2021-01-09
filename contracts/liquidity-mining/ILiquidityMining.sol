//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;

import "./LiquidityMiningData.sol";

interface ILiquidityMining {

    function getRewardTokenData() external view returns(address, bool);
    function setLiquidityMiningSetups(LiquidityMiningSetup[] memory liquidityMiningSetup, uint256[] memory farmingSetupIndexes, bool setPinned, uint256 pinnedIndex) external;

}