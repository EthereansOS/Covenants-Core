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
    address[] liquidityPoolTokenAddresses; // address of the liquidity pool token
    address mainTokenAddress; // eg. buidl address.
    uint256 startBlock; // liquidity mining setup start block (used only if free is false).
    uint256 endBlock; // liquidity mining setup end block (used only if free is false).
    uint256 rewardPerBlock; // liquidity mining setup reward per single block.
    uint256 currentRewardPerBlock; // liquidity mining setup current reward per single block (used only if free is false).
    uint256 maximumLiquidity; // maximum total liquidity (used only if free is false).
    uint256 totalSupply; // current liquidity added in this setup (used only if free is true).
    uint256 lastBlockUpdate; // number of the block where an update was triggered.
    bool free; // if the setup is a free liquidity mining setup or a locked one.
    bool renewable; // if the locked setup is renewable or if it's one time (used only if free is false).
    uint256 penaltyFee; // fee paid when the user exits a still active locked liquidity mining setup (used only if free is false).
}

// position struct
struct LiquidityMiningPosition {
    address uniqueOwner; // address representing the extension address, address(0) if objectId is populated.
    uint256 setupIndex; // the setup index.
    uint256 setupStartBlock; // liquidity mining setup start block (used only if free is false).
    uint256 setupEndBlock; // liquidity mining setup end block (used only if free is false).
    bool free; // if the setup is a free liquidity mining setup or a locked one.
    address ammPlugin; // amm plugin address used for this setup (eg. uniswap amm plugin address).
    LiquidityPoolData liquidityPoolData; // amm liquidity pool data.
    uint256 reward; // position reward.
    uint256 lockedRewardPerBlock; // position locked reward per block.
    uint256 creationBlock; // block when this position was created.
}

// stake data struct
struct LiquidityMiningPositionRequest {
    uint256 setupIndex; // index of the chosen setup.
    uint256 liquidityPoolAddressIndex; // address of the secondary token.
    uint256 liquidityPoolTokenAmount; // amount of liquidity pool token.
    uint256 mainTokenAmount; // amount of main token.
    address positionOwner; // position extension or address(0) [msg.sender].
    bool mintPositionToken; // if the position will be represented by a minted item or not.
    bool ethInvolved; // whether eth is involved in the request or not.
}