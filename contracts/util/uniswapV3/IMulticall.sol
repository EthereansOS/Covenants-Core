//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

interface IMulticall {
    function multicall(bytes[] memory data) external payable returns (bytes[] memory results);
}
