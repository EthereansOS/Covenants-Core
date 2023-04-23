//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AMM.sol";
import "../../util/uniswapV3/IUniswapV3Pool.sol";
import "../../util/uniswapV3/IUniswapV3Factory.sol";
import "../../util/uniswapV3/INonfungiblePositionManager.sol";
import "../../util/uniswapV3/ISwapRouter.sol";
import "../../util/uniswapV3/IMulticall.sol";
import "../../util/uniswapV3/IPeripheryPayments.sol";
import "../../util/uniswapV3/IQuoter.sol";
import "../../util/uniswapV3/TickMath.sol";

contract UniswapV3AMMV1 is AMM {

    uint256 private constant ONE_HUNDRED = 1e18;

    bytes32 private constant POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    address public immutable nonfungiblePositionManagerAddress;
    address public immutable factoryAddress;
    address public immutable swapRouterAddress;
    address public immutable quoterAddress;

    constructor(address _swapRouterAddress, address _nonfungiblePositionManagerAddress, address _quoterAddress) AMM("UniswapV3", 1, INonfungiblePositionManager(_nonfungiblePositionManagerAddress).WETH9(), 2, true) {
        factoryAddress = INonfungiblePositionManager(nonfungiblePositionManagerAddress = _nonfungiblePositionManagerAddress).factory();
        swapRouterAddress = _swapRouterAddress;
        quoterAddress = _quoterAddress;
    }

    function balanceOf(uint256 liquidityPoolId, address) public virtual override view returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, address[] memory liquidityPoolTokens) {
        (
            ,
            ,
            address token0,
            address token1,
            ,
            ,
            ,
            uint128 liquidity,
            ,
            ,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = INonfungiblePositionManager(nonfungiblePositionManagerAddress).positions(liquidityPoolId);
        liquidityPoolAmount = liquidity;
        liquidityPoolTokens = new address[](2);
        liquidityPoolTokens[0] = token0;
        liquidityPoolTokens[1] = token1;
        liquidityPoolTokenAmounts = new uint256[](2);
        liquidityPoolTokenAmounts[0] = tokensOwed0;
        liquidityPoolTokenAmounts[1] = tokensOwed1;
    }

    function _decodeAdditionalData(bytes memory additionalData) private pure returns(uint24 fee, int24 tickLower, int24 tickUpper) {
        if(additionalData.length != 0) {
            return abi.decode(additionalData, (uint24, int24, int24));
        }
    }

    function _checkTicks(int24 tickLower, int24 tickUpper) private pure {
        require(tickLower < tickUpper, 'TLU');
        require(tickLower >= TickMath.MIN_TICK, 'TLM');
        require(tickUpper <= TickMath.MAX_TICK, 'TUM');
    }

    function byLiquidityPool(uint256 liquidityPoolId) public override view returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, address[] memory tokenAddresses) {

        (address token0, address token1, , address liquidityPoolAddress) = _getPoolData(liquidityPoolId);

        if(token0 != address(0)) {
            IUniswapV3Pool pool = IUniswapV3Pool(liquidityPoolAddress);
            liquidityPoolAmount = uint256(pool.maxLiquidityPerTick());
            liquidityPoolTokenAmounts = new uint256[](2);
            tokenAddresses = new address[](2);
            tokenAddresses[0] = token0;
            tokenAddresses[1] = token1;
            liquidityPoolTokenAmounts[0] = IERC20Full(tokenAddresses[0]).balanceOf(liquidityPoolAddress);
            liquidityPoolTokenAmounts[1] = IERC20Full(tokenAddresses[1]).balanceOf(liquidityPoolAddress);
        }
    }

    function byTokens(address[] memory tokenAddresses, bytes calldata additionalData) public override view returns(uint256 liquidityPoolAmount, uint256[] memory liquidityPoolTokenAmounts, uint256 liquidityPoolId, address[] memory tokens) {
        (uint24 fee,,) = _decodeAdditionalData(additionalData);
        address liquidityPoolAddress = IUniswapV3Factory(factoryAddress).getPool(tokenAddresses[0], tokenAddresses[1], fee);
        if(liquidityPoolAddress != address(0)) {
            IUniswapV3Pool pool = IUniswapV3Pool(liquidityPoolAddress);
            liquidityPoolAmount = uint256(pool.maxLiquidityPerTick());
            liquidityPoolTokenAmounts = new uint256[](2);
            liquidityPoolId = _toNumber(liquidityPoolAddress);
            tokens = new address[](2);
            tokens[0] = pool.token0();
            tokens[1] = pool.token1();
            liquidityPoolTokenAmounts[0] = IERC20Full(tokens[0]).balanceOf(liquidityPoolAddress);
            liquidityPoolTokenAmounts[1] = IERC20Full(tokens[1]).balanceOf(liquidityPoolAddress);
        }
    }

    function _asPoolAddress(uint256 liquidityPoolId) private view returns(address liquidityPoolAddress) {
        liquidityPoolAddress = _toAddress(liquidityPoolId);
        bytes32 codeHash;
        assembly {
            codeHash := extcodehash(liquidityPoolAddress)
        }
        liquidityPoolAddress = codeHash == POOL_INIT_CODE_HASH ? liquidityPoolAddress : address(0);
    }

    function _getPoolData(uint256 liquidityPoolId) private view returns(address token0, address token1, uint24 poolFee, address liquidityPoolAddress) {
        liquidityPoolAddress = _asPoolAddress(liquidityPoolId);
        if(liquidityPoolAddress != address(0)) {
            IUniswapV3Pool pool = IUniswapV3Pool(liquidityPoolAddress);
            return (pool.token0(), pool.token1(), pool.fee(), liquidityPoolAddress);
        }

        try INonfungiblePositionManager(nonfungiblePositionManagerAddress).positions(liquidityPoolId) returns(uint96, address, address token0Out, address token1Out, uint24 feeOut, int24, int24, uint128, uint256, uint256, uint128, uint128) {
            token0 = token0Out;
            token1 = token1Out;
            poolFee = feeOut;
        } catch {}
        if(poolFee != 0) {
            liquidityPoolAddress = IUniswapV3Factory(factoryAddress).getPool(token0, token1, poolFee);
        } else {
            poolFee = uint24(liquidityPoolId);
        }
    }

    function _getFees(uint256[] memory liquidityPoolIds) private view returns(uint24[] memory fees) {
        fees = new uint24[](liquidityPoolIds.length);
        for(uint256 i = 0; i < fees.length; i++) {
            (,,fees[i],) = _getPoolData(liquidityPoolIds[i]);
        }
    }

    function _getSwapOutput(uint256 value, uint256[] memory liquidityPoolIds, address[] memory path) view internal override returns(uint256) {
        return IQuoter(quoterAddress).quoteExactInput(_toPath(liquidityPoolIds, address(0), path, false), value);
    }

    function _getSwapInput(uint256 value, uint256[] memory liquidityPoolIds, address[] memory path) view internal override returns(uint256) {
        return IQuoter(quoterAddress).quoteExactOutput(_toPath(liquidityPoolIds, address(0), path, true), value);
    }

    function _toPath(uint256[] memory liquidityPoolIds, address firstToken, address[] memory pathInput, bool reverse) private view returns(bytes memory path) {
        address[] memory pathArray = reverse ? _reverse(_preparePathInput(firstToken, pathInput)) : _preparePathInput(firstToken, pathInput);
        uint24[] memory fees = reverse ? _getFees(_reverse(liquidityPoolIds)) : _getFees(liquidityPoolIds);
        require(fees.length == pathArray.length - 1, "length");
        path = abi.encodePacked(pathArray[0], fees[0], pathArray[1]);
        for(uint256 i = 1; i < fees.length; i++) {
            path = abi.encodePacked(path, fees[i], pathArray[i + 1]);
        }
    }

    function _preparePathInput(address firstToken, address[] memory path) private pure returns(address[] memory) {
        if(firstToken == address(0)) {
            return path;
        }
        address[] memory pathInput = new address[](path.length + 1);
        pathInput[0] = firstToken;
        for(uint256 i = 0; i < path.length; i++) {
            pathInput[i + 1] = path[i];
        }
        return pathInput;
    }

    function _getLiquidityPoolOperator(uint256, address[] memory, bytes memory) internal override virtual view returns(address) {
        return nonfungiblePositionManagerAddress;
    }

    function _getLiquidityPoolCreationOperator(address[] memory, uint256[] memory, bool, bytes memory) internal virtual view override returns(address) {
        return nonfungiblePositionManagerAddress;
    }

    function _getSwapOperator(uint256, address[] memory, bytes memory) internal override virtual view returns(address) {
        return swapRouterAddress;
    }

    function checkByTokensAdditionalData(address[] calldata, bytes calldata additionalData) external override pure {
        (uint24 fee,,) = _decodeAdditionalData(additionalData);
        require(fee != 0, "fee");
    }

    function checkAddLiquidityEnsuringPoolAdditionalData(LiquidityPoolCreationParams[] calldata liquidityPoolCreationParams) external override pure {
        for(uint256 i = 0; i < liquidityPoolCreationParams.length; i++) {
            (uint24 fee, int24 tickLower, int24 tickUpper) = _decodeAdditionalData(liquidityPoolCreationParams[i].additionalData);
            require(fee != 0, "fee");
            _checkTicks(tickLower, tickUpper);
        }
    }

    function _checkAddLiquidityAdditionalData(ProcessedLiquidityPoolParams[] memory processedLiquidityPoolParams) internal override view {
        for(uint256 i = 0; i < processedLiquidityPoolParams.length; i++) {
            (,, uint256 poolDataFee, address liquidityPoolAddress) = _getPoolData(processedLiquidityPoolParams[i].liquidityPoolId);
            if(liquidityPoolAddress != address(0) && uint256(uint160(liquidityPoolAddress)) != processedLiquidityPoolParams[i].liquidityPoolId) {
                continue;
            }
            (uint24 fee, int24 tickLower, int24 tickUpper) = _decodeAdditionalData(processedLiquidityPoolParams[i].additionalData);
            require(poolDataFee != 0 || fee != 0, "fee");
            _checkTicks(tickLower, tickUpper);
        }
    }

    function _checkRemoveLiquidityAdditionalData(ProcessedLiquidityPoolParams[] memory) internal override view {}
    function _checkSwapAdditionalData(ProcessedSwapParams[] memory) internal override view {}

    function _retrieveLiquidityPoolIdAndApprove(ProcessedLiquidityPoolParams memory processedLiquidityPoolParams) internal virtual override {
        _tryTransferNFT(processedLiquidityPoolParams.liquidityPoolId);
    }

    function _retrieveLiquidityPoolIdsAndApprove(ProcessedLiquidityPoolParams[] memory processedLiquidityPoolParamsArray) internal virtual override {
        if(_delegateMode()) {
            return;
        }
        for(uint256 i = 0; i < processedLiquidityPoolParamsArray.length; i++) {
            _tryTransferNFT(processedLiquidityPoolParamsArray[i].liquidityPoolId);
        }
    }

    function _tryTransferNFT(uint256 liquidityPoolId) private {
        if(_delegateMode()) {
            return;
        }
        address liquidityPoolAddress = _asPoolAddress(liquidityPoolId);
        if(liquidityPoolAddress != address(uint160(liquidityPoolId))) {
            INonfungiblePositionManager(nonfungiblePositionManagerAddress).transferFrom(msg.sender, address(this), liquidityPoolId);
        }
    }

    function _createLiquidityPoolAndAddLiquidity(LiquidityPoolCreationParams memory params) internal override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId, address[] memory orderedTokens) {
        (uint24 fee, int24 tickLower, int24 tickUpper) = _decodeAdditionalData(params.additionalData);
        orderedTokens = params.tokenAddresses;
        tokensAmounts = new uint256[](2);
        uint256 ethValue = 0;
        address ethereumAddress = _ethereumAddress;
        if(params.involvingETH) {
            for(uint256 i = 0; i < orderedTokens.length; i++) {
                if(orderedTokens[i] == ethereumAddress) {
                    ethValue = params.amounts[i];
                    break;
                }
            }
        }
        (liquidityPoolId, liquidityPoolAmount, tokensAmounts[0], tokensAmounts[1]) = _mint(orderedTokens[0], orderedTokens[1], fee, tickLower, tickUpper, params.amounts[0], params.amounts[1], params.minAmounts[0], params.minAmounts[1], params.receiver, params.deadline, ethValue);
    }

    function _addLiquidity(ProcessedLiquidityPoolParams memory params) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, uint256 liquidityPoolId) {

        address liquidityPoolAddress = _asPoolAddress(params.liquidityPoolId);

        tokensAmounts = new uint256[](2);
        uint256 ethValue = 0;
        address ethereumAddress = _ethereumAddress;
        if(params.involvingETH) {
            for(uint256 i = 0; i < params.liquidityPoolTokens.length; i++) {
                if(params.liquidityPoolTokens[i] == ethereumAddress) {
                    ethValue = params.tokensAmounts[i];
                    break;
                }
            }
        }

        if(liquidityPoolAddress == address(uint160(params.liquidityPoolId))) {
            (uint24 fee, int24 tickLower, int24 tickUpper) = _decodeAdditionalData(params.additionalData);
            (liquidityPoolId, liquidityPoolAmount, tokensAmounts[0], tokensAmounts[1]) = _mint(params.liquidityPoolTokens[0], params.liquidityPoolTokens[1], fee, tickLower, tickUpper, params.tokensAmounts[0], params.tokensAmounts[1], params.minAmounts[0], params.minAmounts[1], params.receiver, params.deadline, ethValue);
        } else {
            (liquidityPoolId, liquidityPoolAmount, tokensAmounts[0], tokensAmounts[1]) = _increaseLiquidity(params.liquidityPoolId, params.tokensAmounts[0], params.tokensAmounts[1], params.minAmounts[0], params.minAmounts[1], params.deadline, ethValue);
            if(params.receiver != address(this)) {
                INonfungiblePositionManager(nonfungiblePositionManagerAddress).safeTransferFrom(address(this), params.receiver, liquidityPoolId, "");
            }
        }
    }

    function _removeLiquidity(ProcessedLiquidityPoolParams memory params) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {
        INonfungiblePositionManager nonfungiblePositionManager = INonfungiblePositionManager(nonfungiblePositionManagerAddress);
        tokensAmounts = new uint256[](2);
        bool involvingETH = params.involvingETH;
        bytes[] memory data = new bytes[](involvingETH ? 4 : 2);
        data[0] = abi.encodeWithSelector(nonfungiblePositionManager.decreaseLiquidity.selector, INonfungiblePositionManager.DecreaseLiquidityParams(
            params.liquidityPoolId,
            uint128(liquidityPoolAmount = params.liquidityPoolAmount),
            params.minAmounts[0],
            params.minAmounts[1],
            params.deadline
        ));

        data[1] = abi.encodeWithSelector(nonfungiblePositionManager.collect.selector, INonfungiblePositionManager.CollectParams({
            tokenId: params.liquidityPoolId,
            recipient: involvingETH ? address(0) : params.receiver,
            amount0Max: 0xffffffffffffffffffffffffffffffff,
            amount1Max: 0xffffffffffffffffffffffffffffffff
        }));
        if(involvingETH) {
            data[2] = abi.encodeWithSelector(nonfungiblePositionManager.unwrapWETH9.selector, 0, params.receiver);
            data[3] = abi.encodeWithSelector(nonfungiblePositionManager.sweepToken.selector, params.liquidityPoolTokens[params.liquidityPoolTokens[0] == _ethereumAddress ? 1 : 0], 0, params.receiver);
        }
        (tokensAmounts[0], tokensAmounts[1]) = abi.decode(IMulticall(address(nonfungiblePositionManager)).multicall(data)[1], (uint256, uint256));
    }

    function _mint(address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, address recipient, uint256 deadline, uint256 ethValue) private returns(uint256 tokenId, uint256 liquidity, uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager nonfungiblePositionManager = INonfungiblePositionManager(nonfungiblePositionManagerAddress);
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams(
            token0,
            token1,
            fee,
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min,
            recipient,
            deadline
        );
        if(ethValue == 0) {
            (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(mintParams);
            return (tokenId, liquidity, amount0, amount1);
        }
        bytes[] memory multicallData = new bytes[](2);
        multicallData[0] = abi.encodeWithSelector(nonfungiblePositionManager.mint.selector, mintParams);
        multicallData[1] = abi.encodeWithSelector(nonfungiblePositionManager.refundETH.selector);
        (tokenId, liquidity, amount0, amount1) = abi.decode(nonfungiblePositionManager.multicall{value : ethValue}(multicallData)[0], (uint256, uint128, uint256, uint256));
    }

    function _increaseLiquidity(uint256 tokenIdInput, uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, uint256 deadline, uint256 ethValue) private returns(uint256 tokenId, uint256 liquidity, uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager nonfungiblePositionManager = INonfungiblePositionManager(nonfungiblePositionManagerAddress);
        INonfungiblePositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = INonfungiblePositionManager.IncreaseLiquidityParams(
            tokenId = tokenIdInput,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min,
            deadline
        );
        if(ethValue == 0) {
            (liquidity, amount0, amount1) = nonfungiblePositionManager.increaseLiquidity(increaseLiquidityParams);
            return (tokenId, liquidity, amount0, amount1);
        }
        bytes[] memory multicallData = new bytes[](2);
        multicallData[0] = abi.encodeWithSelector(nonfungiblePositionManager.increaseLiquidity.selector, increaseLiquidityParams);
        multicallData[1] = abi.encodeWithSelector(nonfungiblePositionManager.refundETH.selector);
        (liquidity, amount0, amount1) = abi.decode(nonfungiblePositionManager.multicall{value : ethValue}(multicallData)[0], (uint128, uint256, uint256));
    }

    function _swap(ProcessedSwapParams memory processedSwapParams) internal override virtual returns(uint256 outputAmount) {
        ISwapRouter.ExactInputParams memory exactInputParams = ISwapRouter.ExactInputParams({
            path : _toPath(processedSwapParams.liquidityPoolIds, processedSwapParams.inputToken, processedSwapParams.path, false),
            recipient : processedSwapParams.exitInETH ? address(0) : processedSwapParams.receiver,
            deadline : processedSwapParams.deadline,
            amountIn : processedSwapParams.amount,
            amountOutMinimum : processedSwapParams.minAmount
        });

        if(processedSwapParams.enterInETH || processedSwapParams.exitInETH) {
            return _swapMulticall(processedSwapParams.enterInETH, processedSwapParams.exitInETH, processedSwapParams.amount, processedSwapParams.receiver, abi.encodeWithSelector(ISwapRouter(swapRouterAddress).exactInput.selector, exactInputParams));
        }
        return ISwapRouter(swapRouterAddress).exactInput(exactInputParams);
    }

    function _swapMulticall(bool enterInETH, bool exitInETH, uint256 value, address recipient, bytes memory data) private returns (uint256) {
        bytes[] memory multicall = new bytes[](enterInETH && exitInETH ? 3 : 2);
        multicall[0] = data;
        if(enterInETH && exitInETH) {
            multicall[1] = abi.encodeWithSelector(IPeripheryPayments(swapRouterAddress).refundETH.selector);
            multicall[2] = abi.encodeWithSelector(IPeripheryPayments(swapRouterAddress).unwrapWETH9.selector, 0, recipient);
        } else {
            multicall[1] = enterInETH ? abi.encodeWithSelector(IPeripheryPayments(swapRouterAddress).refundETH.selector) : abi.encodeWithSelector(IPeripheryPayments(swapRouterAddress).unwrapWETH9.selector, 0, recipient);
        }
        return abi.decode(IMulticall(swapRouterAddress).multicall{value : enterInETH ? value : 0}(multicall)[0], (uint256));
    }
}