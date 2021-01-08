//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;

interface IFixedInflationExtension {

    function receiveTokens(uint256[][] calldata tokenEntries) external;
}