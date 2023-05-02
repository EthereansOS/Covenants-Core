//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/IAMMAggregator.sol";

contract AMMAggregator is IAMMAggregator {

    address public override host;
    mapping(address => bool) public override isAMM;

    address[] private _amms;

    constructor(address _host, address[] memory ammsToAdd) {
        host = _host;
        _add(ammsToAdd);
    }

    modifier authorizedOnly {
        require(msg.sender == host, "Unauthorized");
        _;
    }

    function setHost(address newHost) external override authorizedOnly {
        host = newHost;
    }

    function amms() external override view returns (address[] memory) {
        return _amms;
    }

    function add(address[] memory ammsToAdd) external override authorizedOnly {
        return _add(ammsToAdd);
    }

    function findByLiquidityPool(uint256 liquidityPoolId) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory tokensAddresses, address amm) {
        address[] memory __amms = _amms;
        for(uint256 i = 0; i < __amms.length; i++) {
            try IAMM(amm = __amms[i]).byLiquidityPool(liquidityPoolId) returns (uint256 _liquidityPoolAmount, uint256[] memory _tokensAmounts, address[] memory _tokensAddresses) {
                if(_tokensAddresses.length > 0) {
                    return (_liquidityPoolAmount, _tokensAmounts, _tokensAddresses, amm);
                }
            } catch {
            }
            amm = address(0);
        }
    }

    function info() external override view returns(string memory, uint256) {}

    function data() external override view returns(address, uint256, bool, uint256, address) {}

    function info(uint256 liquidityPoolId) external override view returns(string memory name, uint256 version, address amm) {
        (,,,amm) = findByLiquidityPool(liquidityPoolId);
        (name, version) = IAMM(amm).info();
    }

    function data(uint256 liquidityPoolId) external override view returns(address ethereumAddress, uint256 maxTokensPerLiquidityPool, bool hasUniqueLiquidityPools, uint256 liquidityPoolTokenType, address liquidityPoolCollectionAddress, address amm) {
        (,,,amm) = findByLiquidityPool(liquidityPoolId);
        (ethereumAddress, maxTokensPerLiquidityPool, hasUniqueLiquidityPools, liquidityPoolTokenType, liquidityPoolCollectionAddress) = IAMM(amm).data();
    }

    function balanceOf(uint256 liquidityPoolId, address owner) external override view returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, address[] memory liquidityPoolTokens) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolId);
        return IAMM(amm).balanceOf(liquidityPoolId, owner);
    }

    function byLiquidityPool(uint256 liquidityPoolId) external override view returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, address[] memory liquidityPoolTokens) {
        (liquidityPoolAmount, liquidityPoolTokenAmounts, liquidityPoolTokens,) = findByLiquidityPool(liquidityPoolId);
    }

    function byTokens(address[] calldata tokens, bytes calldata additionalData) external override view returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, uint256 liquidityPoolId, address[] memory liquidityPoolTokens) {}

    function byPercentage(uint256 liquidityPoolId, uint256 numerator, uint256 denominator) external override view returns (uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, address[] memory liquidityPoolTokens) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolId);
        return IAMM(amm).byPercentage(liquidityPoolId, numerator, denominator);
    }

    function byLiquidityPoolAmount(uint256 liquidityPoolId, uint256 liquidityPoolAmount) external override view returns(uint256[] memory liquidityPoolTokenAmounts, address[] memory liquidityPoolTokens) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolId);
        return IAMM(amm).byLiquidityPoolAmount(liquidityPoolId, liquidityPoolAmount);
    }

    function byTokenAmount(uint256 liquidityPoolId, address tokenAddress, uint256 tokenAmount) external override view returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, address[] memory liquidityPoolTokens) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolId);
        return IAMM(amm).byTokenAmount(liquidityPoolId, tokenAddress, tokenAmount);
    }

    function addLiquidityEnsuringPool(LiquidityPoolCreationParams calldata) external payable returns(uint256, uint256[] memory, uint256, address[] memory) {
        revert("Impossibru");
    }

    function addLiquidityEnsuringPoolBatch(LiquidityPoolCreationParams[] calldata) external payable returns(uint256[] memory, uint256[][] memory, uint256[] memory, address[][] memory) {
        revert("Impossibru");
    }

    function addLiquidity(LiquidityPoolParams calldata liquidityPoolParams) external override payable returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, uint256 liquidityPoolId, address[] memory liquidityPoolTokens) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolParams.liquidityPoolId);
        return IAMM(amm).addLiquidity(liquidityPoolParams);
    }

    function addLiquidityBatch(LiquidityPoolParams[] calldata liquidityPoolParams) external override payable returns(uint256[] memory liquidityPoolAmounts, uint256[][] memory liquidityPoolTokenAmounts, uint256[] memory liquidityPoolIds, address[][] memory liquidityPoolTokens) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolParams[0].liquidityPoolId);
        return IAMM(amm).addLiquidityBatch(liquidityPoolParams);
    }

    function removeLiquidity(LiquidityPoolParams calldata liquidityPoolParams) external override returns(uint256 removedLiquidityPoolAmount, uint256[] memory removedLiquidityPoolTokenAmounts, address[] memory liquidityPoolTokens) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolParams.liquidityPoolId);
        return IAMM(amm).removeLiquidity(liquidityPoolParams);
    }

    function removeLiquidityBatch(LiquidityPoolParams[] calldata liquidityPoolParams) external override returns(uint256[] memory removedLiquidityPoolAmounts, uint256[][] memory removedLiquidityPoolTokenAmounts, address[][] memory liquidityPoolTokens) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolParams[0].liquidityPoolId);
        return IAMM(amm).removeLiquidityBatch(liquidityPoolParams);
    }

    function getSwapCounterValue(uint256 amount, bool amountIsLiquidityPool, bool amountIsOutput, uint256[] calldata liquidityPoolIds, address[] calldata path) external override view returns(uint256) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolIds[0]);
        return IAMM(amm).getSwapCounterValue(amount, amountIsLiquidityPool, amountIsOutput, liquidityPoolIds, path);
    }

    function swap(SwapParams calldata swapParams) external override payable returns(uint256 receivedValue) {
        (,,,address amm) = findByLiquidityPool(swapParams.liquidityPoolIds[0]);
        return IAMM(amm).swap(swapParams);
    }

    function swapBatch(SwapParams[] calldata swapParams) external override payable returns(uint256[] memory receivedValues) {
        (,,,address amm) = findByLiquidityPool(swapParams[0].liquidityPoolIds[0]);
        return IAMM(amm).swapBatch(swapParams);
    }

    function checkByTokensAdditionalData(address[] calldata, bytes calldata) external override pure {
        revert("Impossibru");
    }

    function checkAddLiquidityEnsuringPoolAdditionalData(LiquidityPoolCreationParams[] calldata) external override pure {
        revert("Impossibru");
    }

    function checkAddLiquidityAdditionalData(LiquidityPoolParams[] calldata liquidityPoolParams) external override view {
        (,,,address amm) = findByLiquidityPool(liquidityPoolParams[0].liquidityPoolId);
        return IAMM(amm).checkAddLiquidityAdditionalData(liquidityPoolParams);
    }

    function checkRemoveLiquidityAdditionalData(LiquidityPoolParams[] calldata liquidityPoolParams) external override view {
        (,,,address amm) = findByLiquidityPool(liquidityPoolParams[0].liquidityPoolId);
        return IAMM(amm).checkRemoveLiquidityAdditionalData(liquidityPoolParams);
    }

    function checkSwapAdditionalData(SwapParams[] calldata swapParams) external override view {
        (,,,address amm) = findByLiquidityPool(swapParams[0].liquidityPoolIds[0]);
        return IAMM(amm).checkSwapAdditionalData(swapParams);
    }

    function _add(address[] memory ammsToAdd) private {
        if(ammsToAdd.length == 0) {
            return;
        }
        for(uint256 i = 0 ; i < ammsToAdd.length; i++) {
            if(ammsToAdd[i] == address(0)) {
                continue;
            }
            _amms.push(ammsToAdd[i]);
            isAMM[ammsToAdd[i]] = true;
            (string memory name, uint256 version) = IAMM(ammsToAdd[i]).info();
            emit AMM(ammsToAdd[i], name, version);
        }
    }
}