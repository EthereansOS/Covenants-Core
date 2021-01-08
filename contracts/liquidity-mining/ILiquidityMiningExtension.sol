//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./util/DFOHub.sol";
import "./FarmingSetup.sol";

interface ILiquidityMiningExtension {

    function init(address doubleProxyAddress) external;
    function transferTo(uint256 amount, address recipient) external;
    function backToYou(uint256 amount) external;
    function setFarmingSetups(FarmingSetup[] memory farmingSetups, uint256[] memory farmingSetupIndexes, address liquidityMiningContractAddress, bool setPinned, uint256 pinnedIndex) external;
} 