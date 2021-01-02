//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

interface ILiquidityMining {

    function getRewardTokenData() external view returns(address, bool);
    
}