/*struct LiquidityMiningSetup {
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
}*/

/*{
    ammPlugin:, // amm plugin address used for this setup (eg. uniswap amm plugin address).
    objectId:, // items object id for the liquidity pool token.
    liquidityPoolTokenAddress:, // address of the liquidity pool token
    mainTokenAddress:, // eg. buidl address.
    startBlock:, // liquidity mining setup start block (used only if free is false).
    endBlock:, // liquidity mining setup end block (used only if free is false).
    rewardPerBlock:, // liquidity mining setup reward per single block.
    currentRewardPerBlock:, // liquidity mining setup current reward per single block.
    totalSupply:, // current liquidity added in this setup (used only if free is true).
    lastBlockUpdate:, // number of the block where an update was triggered.
    maximumLiquidity:, // maximum liquidity stakeable in the contract (used only if free is false).
    currentStakedLiquidity:, // currently staked liquidity (used only if free is false).
    free:, // if the setup is a free liquidity mining setup or a locked one.
    renewTimes:, // if the locked setup is renewable or if it's one time (used only if free is false).
    penaltyFee:, // fee paid when the user exits a still active locked liquidity mining setup (used only if free is false).
    involvingETH:, // if the setup involves ETH or not.
}*/

var buidlSetups = [{
    ammPlugin: "0xFC1665BD717dB247CDFB3a08b1d496D1588a6340", // amm plugin address used for this setup (eg. uniswap amm plugin address).
    objectId: 0, // items object id for the liquidity pool token.
    liquidityPoolTokenAddress: "0x04840Eaa3497E4C3934698ff88050Ceb9893f78F", // address of the liquidity pool token
    mainTokenAddress: "0x9E78b8274e1D6a76a0dBbf90418894DF27cBCEb5", // eg. buidl address.
    startBlock: 0, // liquidity mining setup start block (used only if free is false).
    endBlock: 0, // liquidity mining setup end block (used only if free is false).
    rewardPerBlock: utilities.toDecimals("0.08", 18), // liquidity mining setup reward per single block.
    currentRewardPerBlock: 0, // liquidity mining setup current reward per single block.
    totalSupply: 0, // current liquidity added in this setup (used only if free is true).
    lastBlockUpdate: 0, // number of the block where an update was triggered.
    maximumLiquidity: 0, // maximum liquidity stakeable in the contract (used only if free is false).
    currentStakedLiquidity: 0, // currently staked liquidity (used only if free is false).
    free: true, // if the setup is a free liquidity mining setup or a locked one.
    renewTimes: 0, // if the locked setup is renewable or if it's one time (used only if free is false).
    penaltyFee: 0, // fee paid when the user exits a still active locked liquidity mining setup (used only if free is false).
    involvingETH: true, // if the setup involves ETH or not.
}, {
    ammPlugin: "0xFC1665BD717dB247CDFB3a08b1d496D1588a6340", // amm plugin address used for this setup (eg. uniswap amm plugin address).
    objectId: 0, // items object id for the liquidity pool token.
    liquidityPoolTokenAddress: "0xb0fB35Cc576034b01bED6f4D0333b1bd3859615C", // address of the liquidity pool token
    mainTokenAddress: "0x7b123f53421b1bF8533339BFBdc7C98aA94163db", // eg. buidl address.
    startBlock: 0, // liquidity mining setup start block (used only if free is false).
    endBlock: 0, // liquidity mining setup end block (used only if free is false).
    rewardPerBlock: utilities.toDecimals("0.003", 18), // liquidity mining setup reward per single block.
    currentRewardPerBlock: 0, // liquidity mining setup current reward per single block.
    totalSupply: 0, // current liquidity added in this setup (used only if free is true).
    lastBlockUpdate: 0, // number of the block where an update was triggered.
    maximumLiquidity: 0, // maximum liquidity stakeable in the contract (used only if free is false).
    currentStakedLiquidity: 0, // currently staked liquidity (used only if free is false).
    free: true, // if the setup is a free liquidity mining setup or a locked one.
    renewTimes: 0, // if the locked setup is renewable or if it's one time (used only if free is false).
    penaltyFee: 0, // fee paid when the user exits a still active locked liquidity mining setup (used only if free is false).
    involvingETH: true, // if the setup involves ETH or not.
}, {
    ammPlugin: "0x6F0EebE59afF0734Ebb9E00E0D660921B1Bca123", // amm plugin address used for this setup (eg. uniswap amm plugin address).
    objectId: 0, // items object id for the liquidity pool token.
    liquidityPoolTokenAddress: "0xAa5Bac68C9C655FE7779030031A79084a2984ae5", // address of the liquidity pool token
    mainTokenAddress: "0x9E78b8274e1D6a76a0dBbf90418894DF27cBCEb5", // eg. buidl address.
    startBlock: 0, // liquidity mining setup start block (used only if free is false).
    endBlock: 0, // liquidity mining setup end block (used only if free is false).
    rewardPerBlock: utilities.toDecimals("0.003", 18), // liquidity mining setup reward per single block.
    currentRewardPerBlock: 0, // liquidity mining setup current reward per single block.
    totalSupply: 0, // current liquidity added in this setup (used only if free is true).
    lastBlockUpdate: 0, // number of the block where an update was triggered.
    maximumLiquidity: 0, // maximum liquidity stakeable in the contract (used only if free is false).
    currentStakedLiquidity: 0, // currently staked liquidity (used only if free is false).
    free: true, // if the setup is a free liquidity mining setup or a locked one.
    renewTimes: 0, // if the locked setup is renewable or if it's one time (used only if free is false).
    penaltyFee: 0, // fee paid when the user exits a still active locked liquidity mining setup (used only if free is false).
    involvingETH: true, // if the setup involves ETH or not.
}, {
    ammPlugin: "0x5D0deC4AE7Ec2F0cA9BAB4F4AAB9ec8CBCaFF0A3", // amm plugin address used for this setup (eg. uniswap amm plugin address).
    objectId: 0, // items object id for the liquidity pool token.
    liquidityPoolTokenAddress: "0xB86b7A79A9b8cA2FaFD12a180aC08d4Ee4135e41", // address of the liquidity pool token
    mainTokenAddress: "0x9E78b8274e1D6a76a0dBbf90418894DF27cBCEb5", // eg. buidl address.
    startBlock: 0, // liquidity mining setup start block (used only if free is false).
    endBlock: 0, // liquidity mining setup end block (used only if free is false).
    rewardPerBlock: utilities.toDecimals("0.003", 18), // liquidity mining setup reward per single block.
    currentRewardPerBlock: 0, // liquidity mining setup current reward per single block.
    totalSupply: 0, // current liquidity added in this setup (used only if free is true).
    lastBlockUpdate: 0, // number of the block where an update was triggered.
    maximumLiquidity: 0, // maximum liquidity stakeable in the contract (used only if free is false).
    currentStakedLiquidity: 0, // currently staked liquidity (used only if free is false).
    free: true, // if the setup is a free liquidity mining setup or a locked one.
    renewTimes: 0, // if the locked setup is renewable or if it's one time (used only if free is false).
    penaltyFee: 0, // fee paid when the user exits a still active locked liquidity mining setup (used only if free is false).
    involvingETH: true, // if the setup involves ETH or not.
}, {
    ammPlugin: "0xFC1665BD717dB247CDFB3a08b1d496D1588a6340", // amm plugin address used for this setup (eg. uniswap amm plugin address).
    objectId: 0, // items object id for the liquidity pool token.
    liquidityPoolTokenAddress: "0xadaFB7eCC4Fa0794c7A895Da0a53b153871E59B6", // address of the liquidity pool token
    mainTokenAddress: "0x34612903Db071e888a4dADcaA416d3EE263a87b9", // eg. buidl address.
    startBlock: 0, // liquidity mining setup start block (used only if free is false).
    endBlock: 0, // liquidity mining setup end block (used only if free is false).
    rewardPerBlock: utilities.toDecimals("0.003", 18), // liquidity mining setup reward per single block.
    currentRewardPerBlock: 0, // liquidity mining setup current reward per single block.
    totalSupply: 0, // current liquidity added in this setup (used only if free is true).
    lastBlockUpdate: 0, // number of the block where an update was triggered.
    maximumLiquidity: 0, // maximum liquidity stakeable in the contract (used only if free is false).
    currentStakedLiquidity: 0, // currently staked liquidity (used only if free is false).
    free: true, // if the setup is a free liquidity mining setup or a locked one.
    renewTimes: 0, // if the locked setup is renewable or if it's one time (used only if free is false).
    penaltyFee: 0, // fee paid when the user exits a still active locked liquidity mining setup (used only if free is false).
    involvingETH: true, // if the setup involves ETH or not.
}, {
    ammPlugin: "0xFC1665BD717dB247CDFB3a08b1d496D1588a6340", // amm plugin address used for this setup (eg. uniswap amm plugin address).
    objectId: 0, // items object id for the liquidity pool token.
    liquidityPoolTokenAddress: "0x04840Eaa3497E4C3934698ff88050Ceb9893f78F", // address of the liquidity pool token
    mainTokenAddress: "0x7b123f53421b1bF8533339BFBdc7C98aA94163db", // eg. buidl address.
    startBlock: 11820000, // liquidity mining setup start block (used only if free is false).
    endBlock: 12396000, // liquidity mining setup end block (used only if free is false).
    rewardPerBlock: utilities.toDecimals("0.09968253968", 18), // liquidity mining setup reward per single block.
    currentRewardPerBlock: 0, // liquidity mining setup current reward per single block.
    totalSupply: 0, // current liquidity added in this setup (used only if free is true).
    lastBlockUpdate: 0, // number of the block where an update was triggered.
    maximumLiquidity: utilities.toDecimals("450000", 18), // maximum liquidity stakeable in the contract (used only if free is false).
    currentStakedLiquidity: 0, // currently staked liquidity (used only if free is false).
    free: false, // if the setup is a free liquidity mining setup or a locked one.
    renewTimes: 0, // if the locked setup is renewable or if it's one time (used only if free is false).
    penaltyFee: 0.05 * 10000, // fee paid when the user exits a still active locked liquidity mining setup (used only if free is false).
    involvingETH: true, // if the setup involves ETH or not.
}];