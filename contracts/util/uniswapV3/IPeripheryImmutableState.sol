//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

interface IPeripheryImmutableState {
    function factory() external view returns (address);

    function WETH9() external view returns (address);
}
