//SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

struct AllowedAMM {
    address ammAddress;
    address[] liquidityPools;
}