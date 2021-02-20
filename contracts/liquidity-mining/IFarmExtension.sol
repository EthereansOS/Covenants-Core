//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./FarmData.sol";

interface IFarmExtension {

    function init(bool byMint, address host) external;

    function setHost(address host) external;

    function data() external view returns(address farmMainContract, bool byMint, address host, address rewardTokenAddress);

    function transferTo(uint256 amount) external;
    function backToYou(uint256 amount) external payable;

    function setFarmingSetups(FarmingSetupConfiguration[] memory farmingSetups) external;

    function active() external view returns(bool);
}