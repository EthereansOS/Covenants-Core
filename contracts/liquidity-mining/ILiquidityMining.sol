//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./LiquidityMiningData.sol";

interface ILiquidityMining {

    function _rewardTokenAddress() external view returns(address);
    function setups() external view returns (LiquidityMiningSetup[] memory);
    function setLiquidityMiningSetups(LiquidityMiningSetupConfiguration[] memory liquidityMiningSetups, bool clearPinned, bool setPinned, uint256 pinnedIndex) external;
    function toggleSetups(uint256[] memory setupIndexes, uint256[] memory statuses) external;
}