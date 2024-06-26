//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

struct FarmingPositionRequest {
    uint256 setupIndex; // index of the chosen setup.
    uint256 amount0; // amount of main token or liquidity pool token.
    uint256 amount1; // amount of other token or liquidity pool token. Needed for gen2
    address positionOwner; // position extension or address(0) [msg.sender].
    uint256 amount0Min;
    uint256 amount1Min;
}

struct FarmingSetupConfiguration {
    bool add; // true if we're adding a new setup, false we're updating it.
    bool disable;
    uint256 index; // index of the setup we're updating.
    FarmingSetupInfo info; // data of the new or updated setup
}

struct FarmingSetupInfo {
    uint256 eventDuration; // duration of setup
    uint256 startEvent; // optional start event used for the delayed activation of the first setup
    uint256 originalRewardPerEvent;
    uint256 minStakeable; // minimum amount of staking tokens.
    uint256 renewTimes; // if the setup is renewable or if it's one time.
    address liquidityPoolTokenAddress; // address of the liquidity pool token
    address mainTokenAddress; // eg. buidl address.
    bool involvingETH; // if the setup involves ETH or not.
    uint256 setupsCount; // number of setups created by this info.
    uint256 lastSetupIndex; // index of last setup;
    int24 tickLower; // Gen2 Only - tickLower of the UniswapV3 pool
    int24 tickUpper; // Gen 2 Only - tickUpper of the UniswapV3 pool
}

struct FarmingSetup {
    uint256 infoIndex; // setup info
    bool active; // if the setup is active or not.
    uint256 startEvent; // farming setup start event.
    uint256 endEvent; // farming setup end event.
    uint256 lastUpdateEvent; // number of the event where an update was triggered.
    uint256 deprecatedObjectId; // need for gen2. uniswapV3 NFT position Id
    uint256 rewardPerEvent; // farming setup reward per single event.
    uint128 totalSupply; // Total LP token liquidity of all the positions of this setup
}

struct FarmingPosition {
    address uniqueOwner; // address representing the owner of the position.
    uint256 setupIndex; // the setup index related to this position.
    uint256 creationEvent; // event when this position was created.
    uint256 tokenId; // amount of liquidity pool token in the position.
    uint256 reward; // position reward.
}