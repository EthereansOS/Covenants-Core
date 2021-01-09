//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../amm-aggregator/common/AMMData.sol";

// farming setup struct
struct LiquidityMiningSetup {
    address ammPlugin; // amm plugin address used for this setup (eg. uniswap amm plugin address).
    address liquidityPoolTokenAddress; // address of the liquidity pool token
    uint256 startBlock; // farming setup start block (used only if free is false).
    uint256 endBlock; // farming setup end block (used only if free is false).
    uint256 rewardPerBlock; // farming setup reward per single block.
    uint256 currentRewardPerBlock; // farming setup current reward per single block (used only if free is false).
    uint256 maximumLiquidity; // maximum total liquidity (used only if free is false).
    uint256 totalSupply; // current liquidity added in this setup (used only if free is true).
    uint256 lastBlockUpdate; // number of the block where an update was triggered.
    address mainTokenAddress; // eg. buidl address.
    address[] secondaryTokenAddresses; // eg. [address(0), dai address].
    bool free; // if the setup is a free farming setup or a locked one.
    bool renewable; // if the locked setup is renewable or if it's one time (used only if free is false).
    uint256 penaltyFee; // fee paid when the user exits a still active locked farming setup (used only if free is false).
}

// position struct
struct LiquidityMiningPosition {
    uint256 objectId; // object id representing the position token if minted, 0 if uniqueOwner is populated.
    address uniqueOwner; // address representing the extension address, address(0) if objectId is populated.
    LiquidityMiningSetup setup; // chosen setup when the position was created.
    LiquidityPoolData liquidityPoolData; // amm liquidity pool data.
    uint256 liquidityPoolTokenAmount; // amount of liquidity pool token provided.
    uint256 reward; // position reward.
    uint256 lockedRewardPerBlock; // position locked reward per block.
    uint256 creationBlock; // block when this position was created.
}

// stake data struct
struct LiquidityMiningData {
    uint256 setupIndex; // index of the chosen setup.
    address secondaryTokenAddress; // address of the secondary token.
    uint256 liquidityPoolTokenAmount; // amount of liquidity pool token.
    uint256 mainTokenAmount; // amount of main token.
    uint256 secondaryTokenAmount; // amount of secondary token.
    address positionOwner; // position extension or address(0) [msg.sender].
    bool mintPositionToken; // if the position will be represented by a minted item or not.
}