// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
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
        address[] memory secondaryTokenAddresses = new address[](1);
        secondaryTokenAddresses[0] = {0};
        FarmingSetup[] memory farmingSetups = new FarmingSetup[]({1});
        {2}
        ILiquidityMiningExtension({3}).setFarmingSetups(farmingSetups, {4}, false, 0);
    }
}

interface ILiquidityMiningExtension {
    function setFarmingSetups(FarmingSetup[] memory farmingSetups, address liquidityMiningContractAddress) external;
}

// farming setup struct
struct FarmingSetup {
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
    bool renewable; // if the locked setup is renewable or if it's one time (used only if free is false.)
    uint256 penaltyFee; // fee paid when the user exits a still active locked farming setup (used only if free is false).
}