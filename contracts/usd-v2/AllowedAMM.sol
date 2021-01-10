//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

struct AllowedAMM {
    address ammAddress;
    address[] liquidityPools;
}