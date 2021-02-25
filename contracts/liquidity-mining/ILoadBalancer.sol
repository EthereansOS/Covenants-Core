//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

interface ILoadBalancer {

    function rebalancePinnedSetup(uint256 amount, bool add, uint256 endBlock) external;
}