//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./UniswapV2BasedAMMV1.sol";

interface IBazaarFactory {
    function getFarming(address token0, address token1) external view returns(address farmingAddress);
}

interface IBazaarFarming {
    function claim(address receiver) external returns(uint256 claimedReward, uint256 _nextRebalanceEvent, uint256 rewardPerEvent);
}

contract BazaarAMMV1 is UniswapV2BasedAMMV1 {

    constructor(address _routerAddress) UniswapV2BasedAMMV1("Bazaar", 1, _routerAddress) {}

    function _removeLiquidity(ProcessedLiquidityPoolParams memory processedLiquidityPoolParams) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {
        (liquidityPoolAmount, tokensAmounts) = super._removeLiquidity(processedLiquidityPoolParams);
        IBazaarFarming(IBazaarFactory(factoryAddress).getFarming(processedLiquidityPoolParams.liquidityPoolTokens[0], processedLiquidityPoolParams.liquidityPoolTokens[1])).claim(processedLiquidityPoolParams.receiver);
    }
}