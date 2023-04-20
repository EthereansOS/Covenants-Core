//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct LiquidityPoolCreationData {
    address[] tokenAddresses;
    uint256[] amounts;
    bool involvingETH;
    bytes additionalData;
    uint256[] minAmounts;
    address receiver;
    uint256 deadline;
}

struct LiquidityPoolData {
    uint256 liquidityPoolId;
    uint256 amount;
    address tokenAddress;
    bool amountIsLiquidityPool;
    bool involvingETH;
    bytes additionalData;
    uint256[] minAmounts;
    address receiver;
    uint256 deadline;
}

struct SwapData {
    bool enterInETH;
    bool exitInETH;
    uint256[] liquidityPoolIds;
    address[] path;
    address inputToken;
    uint256 amount;
    bytes additionalData;
    uint256 minAmount;
    address receiver;
    uint256 deadline;
}

interface IAMM {

    event NewLiquidityPool(uint256 indexed liquidityPoolId);

    function info() external view returns(string memory name, uint256 version);

    function data() external view returns(address ethereumAddress, uint256 maxTokensPerLiquidityPool, bool hasUniqueLiquidityPools);

    function balanceOf(uint256 liquidityPoolId, address owner) external view returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, address[] memory liquidityPoolTokens);

    function byLiquidityPool(uint256 liquidityPoolId) external view returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, address[] memory liquidityPoolTokens);

    function byTokens(address[] calldata tokens, bytes calldata additionalData) external view returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, uint256 liquidityPoolId, address[] memory liquidityPoolTokens);

    function byPercentage(uint256 liquidityPoolId, uint256 numerator, uint256 denominator) external view returns (uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, address[] memory liquidityPoolTokens);

    function byLiquidityPoolAmount(uint256 liquidityPoolId, uint256 liquidityPoolAmount) external view returns(uint256[] memory liquidityPoolTokenAmounts, address[] memory liquidityPoolTokens);

    function byTokenAmount(uint256 liquidityPoolId, address tokenAddress, uint256 tokenAmount) external view returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, address[] memory liquidityPoolTokens);

    function addLiquidityEnsuringPool(LiquidityPoolCreationData calldata liquidityPoolCreationData) external payable returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, uint256 liquidityPoolId, address[] memory liquidityPoolTokens);

    function addLiquidity(LiquidityPoolData calldata liquidityPoolData) external payable returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, uint256 liquidityPoolId, address[] memory liquidityPoolTokens);
    function addLiquidityBatch(LiquidityPoolData[] calldata liquidityPoolData) external payable returns(uint256[] memory liquidityPoolAmounts, uint256[][] memory liquidityPoolTokenAmounts, uint256[] memory liquidityPoolIds, address[][] memory liquidityPoolTokens);

    function removeLiquidity(LiquidityPoolData calldata liquidityPoolData) external returns(uint256 removedLiquidityPoolAmount, uint256[] memory removedLiquidityPoolTokenAmounts, address[] memory liquidityPoolTokens);
    function removeLiquidityBatch(LiquidityPoolData[] calldata liquidityPoolData) external returns(uint256[] memory removedLiquidityPoolAmounts, uint256[][] memory removedLiquidityPoolTokenAmounts, address[][] memory liquidityPoolTokens);

    function getSwapOutput(uint256 value, bool valueIsLiquidityPool, uint256[] calldata liquidityPoolIds, address[] calldata path) view external returns(uint256);
    function getSwapInput(uint256 value, bool valueIsLiquidityPool, uint256[] calldata liquidityPoolIds, address[] calldata path) view external returns(uint256);

    function swapLiquidity(SwapData calldata swapData) external payable returns(uint256 receivedValue);
    function swapLiquidityBatch(SwapData[] calldata swapData) external payable returns(uint256[] memory receivedValues);
}