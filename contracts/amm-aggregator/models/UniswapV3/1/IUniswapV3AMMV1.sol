//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "../../../common/IAMM.sol";

interface IUniswapV3AMMV1 is IAMM {

    function uniswapData() external view returns(address factoryAddress, address swapRouterAddress, address nonfungiblePositionManagerAddress, address quoterAddress, address wethAddress);
}