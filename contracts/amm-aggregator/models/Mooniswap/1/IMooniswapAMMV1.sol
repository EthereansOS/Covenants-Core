//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../../../common/IAMM.sol";
import "../../../util/IERC20.sol";

interface IMooniswapAMMV1 is IAMM {

    function factory() external view returns(address);
}

contract IMooniFactory {

    mapping(address => mapping(address => Mooniswap)) public pools;

    function deploy(address tokenA, address tokenB) external returns(Mooniswap pool) {}
    function sortTokens(address tokenA, address tokenB) external pure returns(address, address) {}
}

interface Mooniswap {

    function fee() external view returns(uint256);

    function getTokens() external view returns(address[] memory);

    function decayPeriod() external pure returns(uint256);

    function getBalanceForAddition(address token) external view returns(uint256);

    function getBalanceForRemoval(address token) external view returns(uint256);

    function getReturn(address src, address dst, uint256 amount) external view returns(uint256);

    function deposit(uint256[] calldata amounts, uint256[] calldata minAmounts) external payable returns(uint256 fairSupply);

    function withdraw(uint256 amount, uint256[] memory minReturns) external;

    function swap(address src, address dst, uint256 amount, uint256 minReturn, address referral) external payable returns(uint256 result);
}