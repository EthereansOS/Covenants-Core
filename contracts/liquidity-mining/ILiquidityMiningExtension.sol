//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./LiquidityMiningData.sol";

interface ILiquidityMiningExtension {

    function init(bool byMint, address host) external;

    function setHost(address host) external;

    function data() external view returns(address liquidityMiningContract, bool byMint, address host, address rewardTokenAddress);

    function transferTo(uint256 amount) external;
    function backToYou(uint256 amount) external payable;

    function toggleSetups(uint256[] memory setupIndexes) external;
    function setLiquidityMiningSetups(LiquidityMiningSetupConfiguration[] memory liquidityMiningSetups, bool clearPinned, bool setPinned, uint256 pinnedIndex) external;

    function active() external view returns(bool);
}