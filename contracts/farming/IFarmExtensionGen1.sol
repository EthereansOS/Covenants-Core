//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./FarmDataGen1.sol";
import "./IFinalFlush.sol";

interface IFarmExtensionGen1 is IFinalFlush {

    function init(bool byMint, address host, address treasury) external;

    function setHost(address host) external;
    function setTreasury(address treasury) external;

    function data() external view returns(address farmMainContract, bool byMint, address host, address treasury, address rewardTokenAddress);

    function transferTo(uint256 amount) external;
    function backToYou(uint256 amount) external payable;

    function setFarmingSetups(FarmingSetupConfiguration[] memory farmingSetups) external;

}