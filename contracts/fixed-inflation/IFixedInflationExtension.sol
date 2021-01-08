//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IFixedInflationExtension {

    function receiveToken(address tokenAddress, uint256 tokenAmount, bool byMint, address receiver) external;
}