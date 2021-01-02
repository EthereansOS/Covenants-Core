//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface ILiquidityMiningFactory {

    function _exitFee() external returns(uint256);
    function _wallet() external returns(address);
    
}