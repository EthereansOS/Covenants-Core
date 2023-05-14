//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IRoutines.sol";
import "@ethereansos/swissknife/contracts/generic/model/ILazyInitCapableElement.sol";

interface IRoutinesExtension is ILazyInitCapableElement {
    function active() external view returns(bool);

    function setActive(bool _active) external;

    function setEntry(RoutinesEntry memory entryData, RoutinesOperation[] memory operations) external;

    function flushBack(address[] memory tokenAddresses) external;

    function sendAndMintTokens(address[] memory tokenAddresses, uint256[] memory amountsToTransfer, uint256[] memory amountsToMint) external returns(uint256[] memory transferredAmounts, uint256[] memory mintedAmounts);

    function deactivationByFailure() external;

    function burn(address erc20TokenAddress, uint256 value) external;
}