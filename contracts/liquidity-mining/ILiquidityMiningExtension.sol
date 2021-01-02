//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./util/DFOHub.sol";

interface ILiquidityMiningExtension {

    function init(address doubleProxyAddress) external;
    function transferMe(uint256 amount) external returns(bool);
    function backToYou(uint256 amount) external returns(bool);
} 