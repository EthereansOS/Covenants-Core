//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;

import "./util/DFOHub.sol";
import "./LiquidityMiningData.sol";

interface ILiquidityMiningExtension {

    function init(address doubleProxyAddress, bool byMint) external;
    function transferTo(uint256 amount, address recipient) external;
    function backToYou(uint256 amount) external payable;
    function setLiquidityMiningSetups(address liquidityMiningContractAddress, LiquidityMiningSetupConfiguration[] memory liquidityMiningSetups, bool clearPinned, bool setPinned, uint256 pinnedIndex) external;
} 