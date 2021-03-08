//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./FarmData.sol";

interface IFarmMain {

    function ONE_HUNDRED() external view returns(uint256);    
    function _rewardTokenAddress() external view returns(address);
    function setFarmingSetups(FarmingSetupConfiguration[] memory farmingSetups) external;
}