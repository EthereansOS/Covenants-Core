//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IRoutines.sol";

interface IRoutinesExtension {

    function init(address host) external;

    function setHost(address host) external;

    function data() external view returns(address RoutinesContract, address host);

    function receiveTokens(address[] memory tokenAddresses, uint256[] memory transferAmounts, uint256[] memory amountsToMint) external;

    function flushBack(address[] memory tokenAddresses) external;

    function deactivationByFailure() external;

    function setEntry(RoutinesEntry memory entryData, RoutinesOperation[] memory operations) external;

    function active() external view returns(bool);

    function setActive(bool _active) external;

    function burnToken(address erc20TokenAddress, uint256 value) external;
}