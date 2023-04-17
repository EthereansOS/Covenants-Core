//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "../../../common/IAMM.sol";

interface IUniswapV3AMMV1 is IAMM {

    function uniswapData() external view returns(address factoryAddress, address swapRouterAddress, address nonfungiblePositionManagerAddress, address quoterAddress, address wethAddress);
}