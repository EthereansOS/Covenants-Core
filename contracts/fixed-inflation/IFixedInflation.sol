//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./FixedInflationData.sol";

interface IFixedInflation {

    function setEntry(FixedInflationEntry memory entryData, FixedInflationOperation[] memory operations) external;

    function flushBack(address[] memory tokenAddresses) external;
}