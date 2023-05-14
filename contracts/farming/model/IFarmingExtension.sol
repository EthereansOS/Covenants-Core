//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IFarming.sol";

interface IFarmingExtension {
    function data() external view returns(address farmMainContract, address _host, address rewardTokenAddress, bool byMint, address treasury);

    function setTreasury(address treasury) external;
    function setModels(SetupModelConfiguration[] memory setupModelConfigurationArray) external;

    function transferTo(uint256 amount) external returns(uint256 transferred);
    function backToYou(uint256 amount) external payable;
}