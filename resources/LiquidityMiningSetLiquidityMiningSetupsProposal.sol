// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

contract ProposalCode {

    string private _metadataLink;

    constructor(string memory metadataLink) {
        _metadataLink = metadataLink;
    }

    function getMetadataLink() public view returns(string memory) {
        return _metadataLink;
    }

    function onStart(address, address) public {
    }

    function onStop(address) public {
    }

    function callOneTime(address) public {
        LiquidityMiningSetupConfiguration[] memory liquidityMiningSetups = new LiquidityMiningSetupConfiguration[]({0});
        {1}
        ILiquidityMiningExtension({2}).setLiquidityMiningSetups(liquidityMiningSetups, {3}, {4}, {5});
    }
}

interface ILiquidityMiningExtension {
    function setLiquidityMiningSetups(LiquidityMiningSetupConfiguration[] memory liquidityMiningSetups, bool clearPinned, bool setPinned, uint256 pinnedIndex) external;
}

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