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
        address[] memory liquidityPoolTokenAddresses = new address[](1);
        liquidityPoolTokenAddresses[0] = {0};
        LiquidityMiningSetupConfiguration[] memory liquidityMiningSetups = new LiquidityMiningSetupConfiguration[]({1});
        {2}
        ILiquidityMiningExtension({3}).setLiquidityMiningSetups({4}, liquidityMiningSetups, {5}, {6}, {7});
    }
}

interface ILiquidityMiningExtension {
    function setLiquidityMiningSetups(address liquidityMiningContractAddress, LiquidityMiningSetupConfiguration[] memory liquidityMiningSetups, bool clearPinned, bool setPinned, uint256 pinnedIndex) external;
}

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
    uint256 totalSupply; // current liquidity added in this setup (used only if free is true).
    uint256 lastBlockUpdate; // number of the block where an update was triggered.
    bool free; // if the setup is a free liquidity mining setup or a locked one.
    bool renewable; // if the locked setup is renewable or if it's one time (used only if free is false).
    uint256 penaltyFee; // fee paid when the user exits a still active locked liquidity mining setup (used only if free is false).
}