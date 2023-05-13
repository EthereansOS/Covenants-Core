//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct PositionRequest {
    uint256 setupIndexOrPositionId;
    uint256[] amounts;
    bytes[] permitSignatures;
    uint256[] amountsMin;
    address owner;
}

struct SetupModelConfiguration {
    bool add;
    bool disable;
    uint256 index;
    SetupModel model;
}

struct SetupModel {
    uint256 duration;
    uint256 startEvent;
    uint256 originalRewardPerEvent;
    uint256 minStakeable;
    uint256 renewTimes;
    address amm;
    address ethereumAddress;
    uint256 liquidityPoolTokenType;
    address liquidityPoolCollectionAddress;
    bytes createLiquidityAdditionalData;
    bytes addLiquidityAdditionalData;
    bytes removeLiquidityAdditionalData;
    uint256 liquidityPoolId;
    bool liquidityPoolIdIsUnique;
    address mainTokenAddress;
    address[] tokenAddresses;
    bool involvingETH;
    uint256 setupsCount;
    uint256 lastSetupIndex;
}

struct Setup {
    uint256 modelIndex;
    bool active;
    uint256 startEvent;
    uint256 endEvent;
    uint256 lastUpdateEvent;
    uint256 rewardPerEvent;
    uint256 totalSupply;
}

struct Position {
    address owner;
    uint256 setupIndex;
    uint256 creationEvent;
    uint256 liquidityPoolId;
    uint256 liquidityPoolAmount;
    uint256 reward;
}

interface IFarming {

    event RewardToken(address indexed rewardTokenAddress);
    event PositionOpened(uint256 indexed positionId, address indexed owner);
    event SetupToken(address indexed mainToken, address indexed involvedToken);
    event FarmToken(uint256 indexed objectId, address indexed liquidityPoolToken, uint256 setupIndex, uint256 endEvent);

    function rewardTokenAddress() external view returns(address);
    function models() external view returns (SetupModel[] memory);
    function setModels(SetupModelConfiguration[] memory setupModelConfigurationArray) external;

    function setups() external view returns (Setup[] memory);
    function setup(uint256 setupIndex) external view returns (Setup memory, SetupModel memory);

    function rewardPaidPerSetup(uint256 setupIndex) external view returns(uint256);
    function rewardReceivedPerSetup(uint256 setupIndex) external view returns(uint256);

    function openPosition(PositionRequest calldata request) external payable returns(uint256 positionId);
    function position(uint256 positionId) external view returns(Position memory);
    function addLiquidity(PositionRequest calldata request) external payable;
    function withdrawReward(uint256 positionId) external;
    function removeLiquidity(uint256 positionId, uint256 amount, uint256[] calldata amountsMin, bytes memory burnData) external;
    function calculateReward(uint256 positionId, bool isExt) external view returns(uint256 reward);

    function finalFlush(address[] calldata tokens, uint256[] calldata amounts) external;
}