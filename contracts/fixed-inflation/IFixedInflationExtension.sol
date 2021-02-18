//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./FixedInflationData.sol";

interface IFixedInflationExtension {

    function init(address host) external;

    function setHost(address host) external;

    function data() external view returns(address fixedInflationContract, address host);

    function receiveTokens(address[] memory tokenAddresses, uint256[] memory transferAmounts, uint256[] memory amountsToMint) external;

    function flushBack(address[] memory tokenAddresses) external;

    function deactivationByFailure() external;

    function setEntry(FixedInflationEntry memory entryData, FixedInflationOperation[] memory operations) external;

    function active() external view returns(bool);

    function setActive(bool _active) external;
}