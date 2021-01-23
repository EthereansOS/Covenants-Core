//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma abicoder v2;

interface IWUSDExtensionController {

    function rebalanceByCreditBlockInterval() external view returns(uint256);

    function lastRebalanceByCreditBlock() external view returns(uint256);

    function wusdInfo() external view returns (address, uint256, address);
}