//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./IAMMAggregator.sol";

contract AMMAggregator is IAMMAggregator {

    address public override host;

    uint256 private _ammsLength;
    mapping(uint256 => address) private _amms;

    constructor(address _host, address[] memory ammsToAdd) {
        host = _host;
        for(uint256 i = 0; i < ammsToAdd.length; i++) {
            IAMM amm = IAMM(_amms[_ammsLength++] = ammsToAdd[i]);
            (string memory name, uint256 version) = amm.info();
            emit AMM(ammsToAdd[i], name, version);
        }
    }

    modifier authorizedOnly virtual {
        require(msg.sender == host, "Unauthorized action");
        _;
    }

    function setHost(address newHost) public override authorizedOnly {
        host = newHost;
    }

    function amms() public override view returns (address[] memory returnData) {
        returnData = new address[](_ammsLength);
        for(uint256 i = 0 ; i < _ammsLength; i++) {
            returnData[i] = _amms[i];
        }
    }

    function remove(uint256 index) public override authorizedOnly {
        require(index < _ammsLength--, "Invalid index");
        _amms[index] = _amms[_ammsLength];
        delete _amms[_ammsLength];
    }

    function add(address[] memory ammsToAdd) public override authorizedOnly {
        for(uint256 i = 0 ; i < ammsToAdd.length; i++) {
            IAMM amm = IAMM(_amms[_ammsLength++] = ammsToAdd[i]);
            (string memory name, uint256 version) = amm.info();
            emit AMM(ammsToAdd[i], name, version);
        }
    }

    function findByLiquidityPool(address liquidityPoolAddress) public override view returns(uint256, uint256[] memory, address[] memory, address amm) {
        for(uint256 i = 0; i < _ammsLength; i++) {
            try IAMM(amm = _amms[i]).byLiquidityPool(liquidityPoolAddress) returns (uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory tokensAddresses) {
                if(tokensAddresses.length > 0) {
                    return (liquidityPoolAmount, tokensAmounts, tokensAddresses, amm);
                }
            } catch {
            }
            amm = address(0);
        }
    }

    function info() public override view returns(string memory, uint256) {}

    function data() public override view returns(address, uint256, bool) {}

    function info(address liquidityPoolAddress) public override view returns(string memory name, uint256 version, address amm) {
        (,,,amm) = findByLiquidityPool(liquidityPoolAddress);
        (name, version) = IAMM(amm).info();
    }

    function data(address liquidityPoolAddress) public override view returns(address ethereumAddress, uint256 maxTokensPerLiquidityPool, bool hasUniqueLiquidityPools, address amm) {
        (,,,amm) = findByLiquidityPool(liquidityPoolAddress);
        (ethereumAddress, maxTokensPerLiquidityPool, hasUniqueLiquidityPools) = IAMM(amm).data();
    }

    function balanceOf(address liquidityPoolAddress, address owner) public override view returns(uint256, uint256[] memory, address[] memory) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolAddress);
        return IAMM(amm).balanceOf(liquidityPoolAddress, owner);
    }

    function byLiquidityPool(address liquidityPoolAddress) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory tokensAddresses) {
        (liquidityPoolAmount, tokensAmounts, tokensAddresses,) = findByLiquidityPool(liquidityPoolAddress);
    }

    function byTokens(address[] calldata liquidityPoolTokens) public override view returns(uint256, uint256[] memory, address, address[] memory) {}

    function byPercentage(address liquidityPoolAddress, uint256 numerator, uint256 denominator) public override view returns (uint256, uint256[] memory, address[] memory) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolAddress);
        return IAMM(amm).byPercentage(liquidityPoolAddress, numerator, denominator);
    }

    function byLiquidityPoolAmount(address liquidityPoolAddress, uint256 liquidityPoolAmount) public override view returns(uint256[] memory, address[] memory) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolAddress);
        return IAMM(amm).byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount);
    }

    function byTokenAmount(address liquidityPoolAddress, address tokenAddress, uint256 tokenAmount) public override view returns(uint256, uint256[] memory, address[] memory) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolAddress);
        return IAMM(amm).byTokenAmount(liquidityPoolAddress, tokenAddress, tokenAmount);
    }

    function createLiquidityPoolAndAddLiquidity(address[] calldata tokenAddresses, uint256[] calldata amounts, bool involvingETH, address receiver) public override payable returns(uint256, uint256[] memory, address, address[] memory) {
        revert("Impossibru");
    }

    function addLiquidity(LiquidityPoolData calldata data) public override payable returns(uint256, uint256[] memory, address[] memory) {
        (,,,address amm) = findByLiquidityPool(data.liquidityPoolAddress);
        return IAMM(amm).addLiquidity(data);
    }

    function addLiquidityBatch(LiquidityPoolData[] calldata data) public override payable returns(uint256[] memory, uint256[][] memory, address[][] memory) {
        (,,,address amm) = findByLiquidityPool(data[0].liquidityPoolAddress);
        return IAMM(amm).addLiquidityBatch(data);
    }

    function removeLiquidity(LiquidityPoolData calldata data) public override returns(uint256, uint256[] memory, address[] memory) {
        (,,,address amm) = findByLiquidityPool(data.liquidityPoolAddress);
        return IAMM(amm).removeLiquidity(data);
    }

    function removeLiquidityBatch(LiquidityPoolData[] calldata data) public override returns(uint256[] memory, uint256[][] memory, address[][] memory) {
        (,,,address amm) = findByLiquidityPool(data[0].liquidityPoolAddress);
        return IAMM(amm).removeLiquidityBatch(data);
    }

    function getSwapOutput(address tokenAddress, uint256 tokenAmount, address[] calldata liquidityPoolAddresses, address[] calldata path) view public override returns(uint256[] memory) {
        (,,,address amm) = findByLiquidityPool(liquidityPoolAddresses[0]);
        return IAMM(amm).getSwapOutput(tokenAddress, tokenAmount, liquidityPoolAddresses, path);
    }

    function swapLiquidity(SwapData calldata data) public override payable returns(uint256) {
        (,,,address amm) = findByLiquidityPool(data.liquidityPoolAddresses[0]);
        return IAMM(amm).swapLiquidity(data);
    }

    function swapLiquidityBatch(SwapData[] calldata data) public override payable returns(uint256[] memory) {
        (,,,address amm) = findByLiquidityPool(data[0].liquidityPoolAddresses[0]);
        return IAMM(amm).swapLiquidityBatch(data);
    }
}