//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;

import "../../../common/IAMM.sol";
import "../../../util/IERC20.sol";

interface IMooniswapAMMV1 is IAMM {

    function factory() external view returns(address);
}

contract IMooniFactory {

    mapping(IERC20 => mapping(IERC20 => Mooniswap)) public pools;

    function deploy(IERC20 tokenA, IERC20 tokenB) external returns(Mooniswap pool) {}
    function sortTokens(IERC20 tokenA, IERC20 tokenB) external pure returns(IERC20, IERC20) {}
}

interface Mooniswap {

    function fee() external view returns(uint256);

    function getTokens() external view returns(IERC20[] memory);

    function decayPeriod() external pure returns(uint256);

    function getBalanceForAddition(IERC20 token) external view returns(uint256);

    function getBalanceForRemoval(IERC20 token) external view returns(uint256);

    function getReturn(IERC20 src, IERC20 dst, uint256 amount) external view returns(uint256);

    function deposit(uint256[] calldata amounts, uint256[] calldata minAmounts) external payable returns(uint256 fairSupply);

    function withdraw(uint256 amount, uint256[] memory minReturns) external;

    function swap(IERC20 src, IERC20 dst, uint256 amount, uint256 minReturn, address referral) external payable returns(uint256 result);
}