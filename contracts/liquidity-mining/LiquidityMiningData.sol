//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "../amm-aggregator/common/AMMData.sol";

struct LiquidityMiningSetupConfiguration {
    bool add;
    uint256 index;
    LiquidityMiningSetup data;
}

// liquidity mining setup struct
struct LiquidityMiningSetup {
    address ammPlugin; // amm plugin address used for this setup (eg. uniswap amm plugin address).
    uint256 objectId; // items object id for the liquidity pool token.
    address liquidityPoolTokenAddress; // address of the liquidity pool token
    address mainTokenAddress; // eg. buidl address.
    uint256 startBlock; // liquidity mining setup start block (used only if free is false).
    uint256 endBlock; // liquidity mining setup end block (used only if free is false).
    uint256 rewardPerBlock; // liquidity mining setup reward per single block.
    uint256 currentRewardPerBlock; // liquidity mining setup current reward per single block.
    uint256 totalSupply; // current liquidity added in this setup (used only if free is true).
    uint256 lastBlockUpdate; // number of the block where an update was triggered.
    uint256 maximumLiquidity; // maximum liquidity stakeable in the contract (used only if free is false).
    uint256 currentStakedLiquidity; // currently staked liquidity (used only if free is false).
    bool free; // if the setup is a free liquidity mining setup or a locked one.
    uint256 renewTimes; // if the locked setup is renewable or if it's one time (used only if free is false).
    uint256 penaltyFee; // fee paid when the user exits a still active locked liquidity mining setup (used only if free is false).
    bool involvingETH; // if the setup involves ETH or not.
}

// position struct
struct LiquidityMiningPosition {
    address uniqueOwner; // address representing the extension address, address(0) if objectId is populated.
    uint256 setupIndex; // the setup index.
    uint256 setupStartBlock; // liquidity mining setup start block (used only if free is false).
    uint256 setupEndBlock; // liquidity mining setup end block (used only if free is false).
    bool free; // if the setup is a free liquidity mining setup or a locked one.
    // LiquidityPoolData liquidityPoolData; // amm liquidity pool data.
    uint256 liquidityPoolTokenAmount;
    uint256 reward; // position reward.
    uint256 lockedRewardPerBlock; // position locked reward per block.
    uint256 creationBlock; // block when this position was created.
}

// stake data struct
struct LiquidityMiningPositionRequest {
    uint256 setupIndex; // index of the chosen setup.
    uint256 amount; // amount of main token or liquidity pool token.
    bool amountIsLiquidityPool; //true if user wants to directly share the liquidity pool token amount, false to add liquidity to AMM
    address positionOwner; // position extension or address(0) [msg.sender].
}