//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./FarmingSetup.sol";

interface ILiquidityMining {

    function getRewardTokenData() external view returns(address, bool);
    function setFarmingSetups(FarmingSetup[] memory farmingSetups, uint256[] memory farmingSetupIndexes, bool setPinned, uint256 pinnedIndex) external;
    function balanceOf(bytes32 positionKey) external view returns(uint256 balance);
    
}