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

contract UniswapV3AMMV1 is AMM {

    uint256 private constant ONE_HUNDRED = 1e18;

    address public immutable factoryAddress;
    address public immutable swapRouterAddress;
    address public immutable nonfungiblePositionManagerAddress;
    address public immutable quoterAddress;
    address public immutable wethAddress;

    constructor(address _swapRouterAddress, address _nonfungiblePositionManagerAddress, address _quoterAddress) AMM("UniswapV3", 1, wethAddress = INonfungiblePositionManager(nonfungiblePositionManagerAddress = _nonfungiblePositionManagerAddress).WETH9(), 2, true) {
        factoryAddress = INonfungiblePositionManager(nonfungiblePositionManagerAddress).factory();
        swapRouterAddress = swapRouterAddress;
        quoterAddress = quoterAddress;
    }

    function byLiquidityPool(address liquidityPoolAddress) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address[] memory tokenAddresses) {

        IUniswapV3Pool pool = IUniswapV3Pool(liquidityPoolAddress);

        address token0 = pool.token0();
        address token1 = pool.token1();
        if(IUniswapV3Factory(factoryAddress).getPool(token0, token1, pool.fee()) != liquidityPoolAddress) {
            return(0, new uint256[](0), new address[](0));
        }

        liquidityPoolAmount = pool.liquidity();

        tokensAmounts = new uint256[](2);
        (uint256 amountA, uint256 amountB) = (0, 0);
        tokensAmounts[0] = amountA;
        tokensAmounts[1] = amountB;

        tokenAddresses = new address[](2);
        tokenAddresses[0] = token0;
        tokenAddresses[1] = token1;
    }

    function byTokens(address[] calldata tokenAddresses) public override view returns(uint256, uint256[] memory, address liquidityPoolAddress, address[] memory tokens) {
        liquidityPoolAddress = tokenAddresses.length > 2 ? IUniswapV3Factory(factoryAddress).getPool(tokenAddresses[0], tokenAddresses[1], uint24(uint160(tokenAddresses[2]))) : address(0);
        if(tokenAddresses.length == 2) {
            uint24[3] memory fees = [uint24(500), 3000, 10000];
            for(uint256 i = 0; i < fees.length; i++) {
                liquidityPoolAddress = IUniswapV3Factory(factoryAddress).getPool(tokenAddresses[0], tokenAddresses[1], fees[i]);
                if(liquidityPoolAddress != address(0)) {
                    break;
                }
            }
        }
        if(liquidityPoolAddress != address(0)) {
            tokens = new address[](2);
            tokens[0] = IUniswapV3Pool(liquidityPoolAddress).token0();
            tokens[1] = IUniswapV3Pool(liquidityPoolAddress).token1();
        }
    }

    function getSwapOutput(address tokenAddress, uint256 tokenAmount, address[] calldata, address[] calldata path) view public virtual override returns(uint256[] memory) {
    }

    function _getLiquidityPoolOperator(address, address[] memory) internal override virtual view returns(address) {
        return swapRouterAddress;
    }

    function _getLiquidityPoolCreator(address[] memory, uint256[] memory, bool) internal virtual view override returns(address) {
        return nonfungiblePositionManagerAddress;
    }

    function _createLiquidityPoolAndAddLiquidity(address[] memory tokenAddresses, uint256[] memory amounts, bool involvingETH, address, address receiver) internal virtual override returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts, address liquidityPoolAddress, address[] memory orderedTokens) {
    }

    function _addLiquidity(ProcessedLiquidityPoolData memory processedLiquidityPoolData) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {
    }

    function _removeLiquidity(ProcessedLiquidityPoolData memory processedLiquidityPoolData) internal override virtual returns(uint256 liquidityPoolAmount, uint256[] memory tokensAmounts) {
    }

    function _swapLiquidity(ProcessedSwapData memory data) internal override virtual returns(uint256 outputAmount) {
        outputAmount = data.path.length == 1 ? _swapLiquiditySingle(data, true) : _swapLiquidityMultiple(data, true);
        outputAmount = outputAmount == 0 ? data.path.length == 1 ? _swapLiquiditySingle(data, false) : _swapLiquidityMultiple(data, false) : outputAmount;
    }

    function _swapLiquiditySingle(ProcessedSwapData memory data, bool calculateAmountOutMinimum) private returns(uint256) {
        uint24 fee = _retrieveFee(data.liquidityPoolAddresses[0], data.inputToken, data.path[0]);
        ISwapRouter.ExactInputSingleParams memory exactInputSingleParams = ISwapRouter.ExactInputSingleParams({
            tokenIn : data.inputToken,
            tokenOut : data.path[0],
            fee : fee,
            recipient : data.exitInETH ? address(0) : data.receiver,
            deadline : block.timestamp + 10000,
            amountIn : data.amount,
            amountOutMinimum : 0,//calculateAmountOutMinimum ? _calculateAmountOutMinimum(abi.encodeWithSelector(IQuoter(_quoterAddress).quoteExactInputSingle.selector, data.inputToken, data.path[0], fee, data.amount, 0)) : 0,
            sqrtPriceLimitX96 : 0
        });
        if(data.enterInETH || data.exitInETH) {
            return _swapLiquidityMulticall(data.enterInETH, data.exitInETH, data.amount, data.receiver, abi.encodeWithSelector(ISwapRouter(swapRouterAddress).exactInputSingle.selector, exactInputSingleParams));
        }
        return ISwapRouter(swapRouterAddress).exactInputSingle(exactInputSingleParams);
    }

    function _swapLiquidityMultiple(ProcessedSwapData memory data, bool calculateAmountOutMinimum) private returns(uint256) {
        bytes memory path = abi.encodePacked(data.inputToken, _retrieveFee(data.liquidityPoolAddresses[0], data.inputToken, data.path[0]), data.path[0]);
        for(uint256 i = 1; i < data.liquidityPoolAddresses.length; i++) {
            path = abi.encodePacked(path, _retrieveFee(data.liquidityPoolAddresses[i], data.path[i - 1], data.path[i]), data.path[i]);
        }

        ISwapRouter.ExactInputParams memory exactInputParams = ISwapRouter.ExactInputParams({
            path : path,
            recipient : data.exitInETH ? address(0) : data.receiver,
            deadline : block.timestamp + 10000,
            amountIn : data.amount,
            amountOutMinimum : 0//calculateAmountOutMinimum ? _calculateAmountOutMinimum(abi.encodeWithSelector(IQuoter(_quoterAddress).quoteExactInput.selector, path, data.amount)) : 0
        });

        if(data.enterInETH || data.exitInETH) {
            return _swapLiquidityMulticall(data.enterInETH, data.exitInETH, data.amount, data.receiver, abi.encodeWithSelector(ISwapRouter(swapRouterAddress).exactInput.selector, exactInputParams));
        }
        return ISwapRouter(swapRouterAddress).exactInput(exactInputParams);
    }

    function _swapLiquidityMulticall(bool enterInETH, bool exitInETH, uint256 value, address recipient, bytes memory data) private returns (uint256) {
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

    function _retrieveFee(address liquidityPoolAddress, address tokenA, address tokenB) private view returns(uint24 fee) {
        require(liquidityPoolAddress == IUniswapV3Factory(factoryAddress).getPool(tokenA, tokenB, fee = IUniswapV3Pool(liquidityPoolAddress).fee()), "Incoherent LP");
    }

    function _calculateAmountOutMinimum(bytes memory data) private returns(uint256) {
        if(_workingSlippageFree == 0) {
            _workingSlippageFree = slippageFee;
            return 0;
        }
        (bool result, bytes memory resultData) = quoterAddress.call(data);
        return _calculateAndResetSlippage(result ? abi.decode(resultData, (uint256)) : 0);
    }

    function _calculateAndResetSlippage(uint256 amount) private returns(uint256 slippageAmount) {
        slippageAmount = _workingSlippageFree == 0 || amount == 0 ? 0 : (amount - ((amount * ((_workingSlippageFree * 1e18) / ONE_HUNDRED)) / 1e18));
        slippageAmount = slippageAmount > amount ? 0 : slippageAmount;
        _workingSlippageFree = slippageFee;
    }
}