//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/IAMMAggregator.sol";

contract AMMAggregator is IAMMAggregator {

    address public override host;
    mapping(address => bool) public override isAMM;

    uint256 private _ammsLength;
    mapping(uint256 => address) private _amms;

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

    function amms() external override view returns (address[] memory returnData) {
        returnData = new address[](_ammsLength);
        for(uint256 i = 0 ; i < _ammsLength; i++) {
            returnData[i] = _amms[i];
        }
    }

    function add(address[] memory ammsToAdd) external override authorizedOnly {
        return _add(ammsToAdd);
    }

    function findByLiquidityPool(uint256 liquidityPoolId) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory tokensAddresses, address amm) {
        for(uint256 i = 0; i < _ammsLength; i++) {
            try IAMM(amm = _amms[i]).byLiquidityPool(liquidityPoolId) returns (uint256 _liquidityPoolAmount, uint256[] memory _tokensAmounts, address[] memory _tokensAddresses) {
                if(_tokensAddresses.length > 0) {
                    return (_liquidityPoolAmount, _tokensAmounts, _tokensAddresses, amm);
                }
            } catch {
            }
            amm = address(0);
        }
    }

    function info() external override view returns(string memory, uint256) {}

    function data() external override view returns(address, uint256, bool) {}

    function info(uint256 liquidityPoolId) external override view returns(string memory name, uint256 version, address amm) {
        (,,,amm) = findByLiquidityPool(liquidityPoolId);
        (name, version) = IAMM(amm).info();
    }

    function data(uint256 liquidityPoolId) external override view returns(address ethereumAddress, uint256 maxTokensPerLiquidityPool, bool hasUniqueLiquidityPools, address amm) {
        (,,,amm) = findByLiquidityPool(liquidityPoolId);
        (ethereumAddress, maxTokensPerLiquidityPool, hasUniqueLiquidityPools) = IAMM(amm).data();
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

    function addLiquidityEnsuringPool(LiquidityPoolCreationData calldata) external payable returns(uint256, uint256[] memory, uint256, address[] memory) {
        revert("Impossibru");
    }

    function addLiquidity(LiquidityPoolData calldata liquidityPoolData) external override payable returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, uint256 liquidityPoolId, address[] memory liquidityPoolTokens) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolData.liquidityPoolId);
        return IAMM(amm).addLiquidity(liquidityPoolData);
    }

    function addLiquidityBatch(LiquidityPoolData[] calldata liquidityPoolData) external override payable returns(uint256[] memory liquidityPoolAmounts, uint256[][] memory liquidityPoolTokenAmounts, uint256[] memory liquidityPoolIds, address[][] memory liquidityPoolTokens) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolData[0].liquidityPoolId);
        return IAMM(amm).addLiquidityBatch(liquidityPoolData);
    }

    function removeLiquidity(LiquidityPoolData calldata liquidityPoolData) external override returns(uint256 removedLiquidityPoolAmount, uint256[] memory removedLiquidityPoolTokenAmounts, address[] memory liquidityPoolTokens) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolData.liquidityPoolId);
        return IAMM(amm).removeLiquidity(liquidityPoolData);
    }

    function removeLiquidityBatch(LiquidityPoolData[] calldata liquidityPoolData) external override returns(uint256[] memory removedLiquidityPoolAmounts, uint256[][] memory removedLiquidityPoolTokenAmounts, address[][] memory liquidityPoolTokens) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolData[0].liquidityPoolId);
        return IAMM(amm).removeLiquidityBatch(liquidityPoolData);
    }

    function getSwapOutput(uint256 value, bool valueIsLiquidityPool, uint256[] calldata liquidityPoolIds, address[] calldata path) view external override returns(uint256) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolIds[0]);
        return IAMM(amm).getSwapOutput(value, valueIsLiquidityPool, liquidityPoolIds, path);
    }

    function getSwapInput(uint256 value, bool valueIsLiquidityPool, uint256[] calldata liquidityPoolIds, address[] calldata path) view external override returns(uint256) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolIds[0]);
        return IAMM(amm).getSwapInput(value, valueIsLiquidityPool, liquidityPoolIds, path);
    }

    function swapLiquidity(SwapData calldata swapData) external override payable returns(uint256 receivedValue) {
        (,,,address amm) = findByLiquidityPool(swapData.liquidityPoolIds[0]);
        return IAMM(amm).swapLiquidity(swapData);
    }

    function swapLiquidityBatch(SwapData[] calldata swapData) external override payable returns(uint256[] memory receivedValues) {
        (,,,address amm) = findByLiquidityPool(swapData[0].liquidityPoolIds[0]);
        return IAMM(amm).swapLiquidityBatch(swapData);
    }

    function _add(address[] memory ammsToAdd) private {
        if(ammsToAdd.length == 0) {
            return;
        }
        for(uint256 i = 0 ; i < ammsToAdd.length; i++) {
            IAMM amm = IAMM(_amms[_ammsLength++] = ammsToAdd[i]);
            isAMM[ammsToAdd[i]] = true;
            (string memory name, uint256 version) = amm.info();
            emit AMM(ammsToAdd[i], name, version);
        }
    }
}