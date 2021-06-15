//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface IFinalFlush {
    function finalFlush(address[] calldata tokens, uint256[] calldata amounts, address[] calldata receivers) external;
}