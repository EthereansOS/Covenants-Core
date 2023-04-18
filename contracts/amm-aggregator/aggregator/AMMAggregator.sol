//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "./IAMMAggregator.sol";

contract AMMAggregator is IAMMAggregator {

    address public override host;
    mapping(address => bool) public override isAMM;

    uint256 private _ammsLength;
    mapping(uint256 => address) private _amms;

    constructor(address _host, address[] memory ammsToAdd) {
        host = _host;
        _add(ammsToAdd);
    }

    modifier authorizedOnly virtual {
        require(msg.sender == host, "Unauthorized action");
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

    function findByLiquidityPool(address liquidityPoolAddress) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory tokensAddresses, address amm) {
        for(uint256 i = 0; i < _ammsLength; i++) {
            try IAMM(amm = _amms[i]).byLiquidityPool(liquidityPoolAddress) returns (uint256 _liquidityPoolAmount, uint256[] memory _tokensAmounts, address[] memory _tokensAddresses) {
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

    function info(address liquidityPoolAddress) external override view returns(string memory name, uint256 version, address amm) {
        (,,,amm) = findByLiquidityPool(liquidityPoolAddress);
        (name, version) = IAMM(amm).info();
    }

    function data(address liquidityPoolAddress) external override view returns(address ethereumAddress, uint256 maxTokensPerLiquidityPool, bool hasUniqueLiquidityPools, address amm) {
        (,,,amm) = findByLiquidityPool(liquidityPoolAddress);
        (ethereumAddress, maxTokensPerLiquidityPool, hasUniqueLiquidityPools) = IAMM(amm).data();
    }

    function balanceOf(address liquidityPoolAddress, address owner) external override view returns(uint256, uint256[] memory, address[] memory) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolAddress);
        return IAMM(amm).balanceOf(liquidityPoolAddress, owner);
    }

    function byLiquidityPool(address liquidityPoolAddress) external override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory tokensAddresses) {
        (liquidityPoolAmount, tokensAmounts, tokensAddresses,) = findByLiquidityPool(liquidityPoolAddress);
    }

    function byTokens(address[] calldata liquidityPoolTokens) external override view returns(uint256, uint256[] memory, address, address[] memory) {}

    function byPercentage(address liquidityPoolAddress, uint256 numerator, uint256 denominator) external override view returns (uint256, uint256[] memory, address[] memory) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolAddress);
        return IAMM(amm).byPercentage(liquidityPoolAddress, numerator, denominator);
    }

    function byLiquidityPoolAmount(address liquidityPoolAddress, uint256 liquidityPoolAmount) external override view returns(uint256[] memory, address[] memory) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolAddress);
        return IAMM(amm).byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount);
    }

    function byTokenAmount(address liquidityPoolAddress, address tokenAddress, uint256 tokenAmount) external override view returns(uint256, uint256[] memory, address[] memory) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolAddress);
        return IAMM(amm).byTokenAmount(liquidityPoolAddress, tokenAddress, tokenAmount);
    }

    function createLiquidityPoolAndAddLiquidity(address[] calldata, uint256[] calldata, bool, address, uint256[] calldata) public override payable returns(uint256, uint256[] memory, address, address[] memory) {
        revert("Impossibru");
    }

    function addLiquidity(LiquidityPoolData calldata liquidityPoolData) external override payable returns(uint256, uint256[] memory, address[] memory) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolData.liquidityPoolAddress);
        return IAMM(amm).addLiquidity(liquidityPoolData);
    }

    function addLiquidityBatch(LiquidityPoolData[] calldata liquidityPoolData) external override payable returns(uint256[] memory, uint256[][] memory, address[][] memory) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolData[0].liquidityPoolAddress);
        return IAMM(amm).addLiquidityBatch(liquidityPoolData);
    }

    function removeLiquidity(LiquidityPoolData calldata liquidityPoolData) external override returns(uint256, uint256[] memory, address[] memory) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolData.liquidityPoolAddress);
        return IAMM(amm).removeLiquidity(liquidityPoolData);
    }

    function removeLiquidityBatch(LiquidityPoolData[] calldata liquidityPoolData) external override returns(uint256[] memory, uint256[][] memory, address[][] memory) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolData[0].liquidityPoolAddress);
        return IAMM(amm).removeLiquidityBatch(liquidityPoolData);
    }

    function getSwapOutput(address tokenAddress, uint256 tokenAmount, address[] calldata liquidityPoolAddresses, address[] calldata path) view external override returns(uint256[] memory) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolAddresses[0]);
        return IAMM(amm).getSwapOutput(tokenAddress, tokenAmount, liquidityPoolAddresses, path);
    }

    function swapLiquidity(SwapData calldata swapData) external override payable returns(uint256) {
        (,,,address amm) = findByLiquidityPool(swapData.liquidityPoolAddresses[0]);
        return IAMM(amm).swapLiquidity(swapData);
    }

    function swapLiquidityBatch(SwapData[] calldata swapData) external override payable returns(uint256[] memory) {
        (,,,address amm) = findByLiquidityPool(swapData[0].liquidityPoolAddresses[0]);
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