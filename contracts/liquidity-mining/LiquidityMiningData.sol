//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;


struct LiquidityMiningLoadBalancer {
    bool active; // if the load balancer is active or not.
    uint256 setupIndex; // pinned setup index.
    uint256 rewardPerBlock; // total reward per block inside the load balancer.
    uint256 lastToggleBlock; // last time the load balancer was toggled.
}

struct LiquidityMiningPositionRequest {
    uint256 setupIndex; // index of the chosen setup.
    uint256 amount; // amount of main token or liquidity pool token.
    bool amountIsLiquidityPool; //true if user wants to directly share the liquidity pool token amount, false to add liquidity to AMM
    address positionOwner; // position extension or address(0) [msg.sender].
}

struct LiquidityMiningSetupConfiguration {
    bool add; // true if we're adding a new setup, false we're updating it.
    uint256 index; // index of the setup we're updating.
    LiquidityMiningSetup data; // data of the new or updated setup
}

struct LiquidityMiningSetup {
    address ammPlugin; // amm plugin address used for this setup (eg. uniswap amm plugin address).
    address liquidityPoolTokenAddress; // address of the liquidity pool token
    address mainTokenAddress; // eg. buidl address.
    bool involvingETH; // if the setup involves ETH or not.
    uint256 startBlock; // liquidity mining setup start block.
    uint256 duration; // liquidity mining setup duration in end block.
    uint256 endBlock; // liquidity mining setup end block.
    uint256 lastUpdateBlock; // number of the block where an update was triggered.
    uint256 objectId; // items object id for the liquidity pool token (used only if free is false).
    uint256 rewardPerBlock; // liquidity mining setup reward per single block.
    uint256 totalSupply; // current liquidity added in this setup (used only if free is true).
    uint256 maxStakeable; // maximum amount stakeable in the setup (used only if free is false).
    uint256 currentlyStaked; // currently staked amount (used only if free is false).
    uint256 renewTimes; // if the setup is renewable or if it's one time.
    uint256 penaltyFee; // fee paid when the user exits a still active locked liquidity mining setup (used only if free is false).
    bool free; // if the setup is a free liquidity mining setup or a locked one.
    bool active; // if the setup is active or not.
}

struct LiquidityMiningPosition {
    address uniqueOwner; // address representing the owner of the position.
    uint256 setupIndex; // the setup index related to this position.
    uint256 creationBlock; // block when this position was created.
    uint256 liquidityPoolTokenAmount; // amount of liquidity pool token in the position.
    uint256 reward; // position reward (used only if free is false).
    uint256 lockedRewardPerBlock; // position locked reward per block (used only if free is false).
}