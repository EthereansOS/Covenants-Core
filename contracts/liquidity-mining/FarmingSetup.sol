//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

// farming setup struct
struct FarmingSetup {
    address ammPlugin; // amm plugin address used for this setup (eg. uniswap amm plugin address).
    address liquidityPoolTokenAddress; // address of the liquidity pool token
    uint256 startBlock; // farming setup start block (used only if free is false).
    uint256 endBlock; // farming setup end block (used only if free is false).
    uint256 rewardPerBlock; // farming setup reward per single block.
    uint256 maximumLiquidity; // maximum total liquidity (used only if free is false).
    uint256 totalSupply; // current liquidity added in this setup (used only if free is true).
    uint256 lastBlockUpdate; // number of the block where an update was triggered.
    address mainTokenAddress; // eg. buidl address.
    address[] secondaryTokenAddresses; // eg. [address(0), dai address].
    bool free; // if the setup is a free farming setup or a locked one.
}