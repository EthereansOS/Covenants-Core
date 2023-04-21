//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/IPresto.sol";
import "../../amm-aggregator/model/IAMMAggregator.sol";
import "../../util/IERC20.sol";
import "../../util/IERC20Burnable.sol";
import "../../util/uniswapV3/IUniswapV3Pool.sol";
import "../../util/uniswapV3/ISwapRouter.sol";
import "../../util/uniswapV3/IMulticall.sol";
import "../../util/uniswapV3/IPeripheryPayments.sol";
import "../../util/uniswapV3/IPeripheryImmutableState.sol";
import "../../util/uniswapV3/INonfungiblePositionManager.sol";

contract Presto is IPresto {

    uint256 private constant ONE_HUNDRED = 1e18;

    mapping(address => uint256) private _tokenIndex;
    address[] private _tokensToTransfer;
    uint256[] private _tokenAmounts;

    address private _ammAggregator;

    address private immutable _uniswapV3SwapRouterAddress;
    address private immutable _uniswapV3NonfungiblePositionManagerAddress;
    address private immutable _wethTokenAddress;

    constructor(address ammAggregator, address uniswapV3SwapRouterAddress, address uniswapV3NonfungiblePositionManagerAddress) {
        _ammAggregator = ammAggregator;
        _wethTokenAddress = IPeripheryImmutableState(_uniswapV3SwapRouterAddress = uniswapV3SwapRouterAddress).WETH9();
        _uniswapV3NonfungiblePositionManagerAddress = uniswapV3NonfungiblePositionManagerAddress;
    }

    receive() external payable {
    }

    function execute(PrestoOperation[] memory operations) external override payable returns(uint256[] memory outputAmounts) {
        _transferToMe(operations);
        outputAmounts = new uint256[](operations.length);
        for(uint256 i = 0 ; i < operations.length; i++) {
            PrestoOperation memory operation = operations[i];
            if(operation.ammPlugin == address(0)) {
                outputAmounts[i] = operation.inputTokenAmount;
                _transferTo(operation.inputTokenAddress, operation.inputTokenAmount, operation.receivers, operation.receiversPercentages);
            } else if(operation.liquidityPoolAddresses.length == 0) {
                outputAmounts[i] = _addLiquidity(operation);
            } else {
                outputAmounts[i] = _swap(operation);
            }
        }
        _flushAndClear();
    }

    function _transferToMe(PrestoOperation[] memory operations) private {
        _collectTokens(operations);
        for(uint256 i = 0; i < _tokensToTransfer.length; i++) {
            if(_tokensToTransfer[i] == address(0)) {
                require(msg.value == _tokenAmounts[i], "Incorrect ETH value");
            } else {
                _safeTransferFrom(_tokensToTransfer[i], msg.sender, address(this), _tokenAmounts[i]);
            }
        }
    }

    function _collectTokens(PrestoOperation[] memory operations) private {
        address uniswapV3SwapRouterAddress = _uniswapV3SwapRouterAddress;
        address uniswapV3NonfungiblePositionManagerAddress = _uniswapV3NonfungiblePositionManagerAddress;
        address wethTokenAddress = _wethTokenAddress;
        address[] memory amms = IAMMAggregator(_ammAggregator).amms();
        for(uint256 i = 0; i < operations.length; i++) {
            PrestoOperation memory operation = operations[i];
            address ethereumAddress = _checkAMMAndRetrieveEthereumAddress(operation, wethTokenAddress, uniswapV3SwapRouterAddress, uniswapV3NonfungiblePositionManagerAddress, amms);
            if(operation.ammPlugin != address(0) && operation.liquidityPoolAddresses.length == 0) {
                (uint256[] memory amounts, address[] memory tokensAddresses) = IAMM(operation.ammPlugin).byLiquidityPoolAmount(operation.inputTokenAddress, operation.inputTokenAmount);
                bool hasEth = false;
                for(uint256 z = 0; z < tokensAddresses.length; z++) {
                    if(tokensAddresses[z] == ethereumAddress) {
                        hasEth = true;
                    }
                    _collectTokenData(operation.enterInETH && tokensAddresses[z] == ethereumAddress ? address(0) : tokensAddresses[z], amounts[z]);
                }
                require(!operation.enterInETH || hasEth, "Wrong use of enterInETH in addLiquidity");
            } else {
                _collectTokenData(operation.ammPlugin != address(0) && operation.enterInETH ? address(0) : operation.inputTokenAddress, operation.inputTokenAmount);
            }
        }
    }

    function _checkAMMAndRetrieveEthereumAddress(PrestoOperation memory operation, address wethTokenAddress, address uniswapV3SwapRouterAddress, address uniswapV3NonfungiblePositionManagerAddress, address[] memory amms) private view returns(address) {
        if(operation.ammPlugin == address(0)) {
            return address(0);
        }
        if(operation.liquidityPoolAddresses.length != 0 && operation.ammPlugin == uniswapV3SwapRouterAddress) {
            return wethTokenAddress;
        }
        if(operation.liquidityPoolAddresses.length == 0 && operation.ammPlugin == uniswapV3NonfungiblePositionManagerAddress) {
            return wethTokenAddress;
        }
        address ammPlugin = operation.ammPlugin;
        for(uint256 i = 0; i < amms.length; i++) {
            if(amms[i] == ammPlugin) {
                (address ethereumAddress,,) = IAMM(ammPlugin).data();
                return ethereumAddress;
            }
        }
        revert("Unknown AMM");
    }

    function _collectTokenData(address inputTokenAddress, uint256 inputTokenAmount) private {
        if(inputTokenAmount == 0) {
            return;
        }

        uint256 position = _tokenIndex[inputTokenAddress];

        if(_tokensToTransfer.length == 0 || _tokensToTransfer[position] != inputTokenAddress) {
            _tokenIndex[inputTokenAddress] = (position = _tokensToTransfer.length);
            _tokensToTransfer.push(inputTokenAddress);
            _tokenAmounts.push(0);
        }
        _tokenAmounts[position] = _tokenAmounts[position] + inputTokenAmount;
    }

    function _flushAndClear() private {
        for(uint256 i = 0; i < _tokensToTransfer.length; i++) {
            _safeTransfer(_tokensToTransfer[i], msg.sender, _balanceOf(_tokensToTransfer[i]));
            delete _tokenIndex[_tokensToTransfer[i]];
        }
        delete _tokensToTransfer;
        delete _tokenAmounts;
    }

    function _balanceOf(address tokenAddress) private view returns(uint256) {
        if(tokenAddress == address(0)) {
            return address(this).balance;
        }
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function _addLiquidity(PrestoOperation memory operation) private returns (uint256 outputAmount) {
        LiquidityPoolParams memory liquidityPoolData = LiquidityPoolParams(
            operation.inputTokenAddress,
            operation.inputTokenAmount,
            address(0),
            true,
            operation.enterInETH,
            address(this),
            operation.tokenMins
        );
        uint256[] memory tokenAmounts;
        (outputAmount,tokenAmounts,) = IAMM(operation.ammPlugin).addLiquidity{value : operation.enterInETH ? operation.inputTokenAmount : 0}(liquidityPoolData);
        _checkMinAmounts(tokenAmounts, operation.tokenMins);
        _transferTo(operation.inputTokenAddress, outputAmount, operation.receivers, operation.receiversPercentages);
    }

    function _swap(PrestoOperation memory operation) private returns(uint256 outputAmount) {

        uint256 minAmount = operation.tokenMins.length > 0 ? operation.tokenMins[0] : 0;

        address ethereumAddress = _wethTokenAddress;
        if(operation.ammPlugin != _uniswapV3SwapRouterAddress) {
            (ethereumAddress,,) = IAMM(operation.ammPlugin).data();
        }

        if(operation.exitInETH) {
            operation.swapPath[operation.swapPath.length - 1] = ethereumAddress;
        }

        address outputToken = operation.swapPath[operation.swapPath.length - 1];

        SwapParams memory swapData = SwapParams(
            operation.enterInETH,
            operation.exitInETH,
            operation.liquidityPoolAddresses,
            operation.swapPath,
            operation.enterInETH ? ethereumAddress : operation.inputTokenAddress,
            operation.inputTokenAmount,
            address(this),
            operation.tokenMins[0]
        );

        if(swapData.inputToken != address(0) && !swapData.enterInETH) {
            _safeApprove(swapData.inputToken, operation.ammPlugin, swapData.amount);
        }

        outputAmount = operation.ammPlugin == _uniswapV3SwapRouterAddress ? _swapLiquidityUniswapV3(swapData, minAmount) : IAMM(operation.ammPlugin).swap{value : swapData.enterInETH ? operation.inputTokenAmount : 0}(swapData);

        _checkMinAmount(outputAmount, minAmount);

        _transferTo(operation.exitInETH ? address(0) : outputToken, outputAmount, operation.receivers, operation.receiversPercentages);
    }

    function _calculateRewardPercentage(uint256 totalAmount, uint256 rewardPercentage) private pure returns (uint256) {
        return (totalAmount * ((rewardPercentage * 1e18) / ONE_HUNDRED)) / 1e18;
    }

    function _transferTo(address erc20TokenAddress, uint256 totalAmount, address[] memory receivers, uint256[] memory receiversPercentages) private {
        uint256 availableAmount = totalAmount;

        uint256 currentPartialAmount;

        uint256 stillAvailableAmount = availableAmount;

        for(uint256 i = 0; i < receivers.length - 1; i++) {
            _transferTo(erc20TokenAddress, receivers[i], currentPartialAmount = _calculateRewardPercentage(stillAvailableAmount, receiversPercentages[i]));
            availableAmount -= currentPartialAmount;
        }

        _transferTo(erc20TokenAddress, receivers[receivers.length - 1], availableAmount);
    }

    function _transferTo(address erc20TokenAddress, address to, uint256 value) private {
        if(value == 0) {
            return;
        }
        if(erc20TokenAddress == address(0)) {
            (bool result,) = to.call{value:value}("");
            require(result, "ETH transfer failed");
            return;
        }
        if(to != address(0)) {
            _safeTransfer(erc20TokenAddress, to, value);
        } else {
            try IERC20Burnable(erc20TokenAddress).burn(value) {
            } catch {
                _safeTransfer(erc20TokenAddress, address(0), value);
            }
        }
    }

    function _safeApprove(address erc20TokenAddress, address to, uint256 value) internal {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).approve.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'APPROVE_FAILED');
    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) private {
        if(value == 0) {
            return;
        }
        if(erc20TokenAddress == address(0)) {
            (bool result,) = to.call{value:value}("");
            require(result, "ETH transfer failed");
            return;
        }
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFER_FAILED');
    }

    function _safeTransferFrom(address erc20TokenAddress, address from, address to, uint256 value) internal {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).transferFrom.selector, from, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFERFROM_FAILED');
    }

    function _call(address location, bytes memory payload) private returns(bytes memory returnData) {
        assembly {
            let result := call(gas(), location, 0, add(payload, 0x20), mload(payload), 0, 0)
            let size := returndatasize()
            returnData := mload(0x40)
            mstore(returnData, size)
            let returnDataPayloadStart := add(returnData, 0x20)
            returndatacopy(returnDataPayloadStart, 0, size)
            mstore(0x40, add(returnDataPayloadStart, size))
            switch result case 0 {revert(returnDataPayloadStart, size)}
        }
    }

    function _swapLiquidityUniswapV3(SwapParams memory data, uint256 amountOutMinimum) private returns(uint256) {
        bytes memory path = abi.encodePacked(data.inputToken, IUniswapV3Pool(data.liquidityPoolAddresses[0]).fee(), data.path[0]);
        for(uint256 i = 1; i < data.liquidityPoolAddresses.length; i++) {
            path = abi.encodePacked(path, IUniswapV3Pool(data.liquidityPoolAddresses[i]).fee(), data.path[i]);
        }

        ISwapRouter.ExactInputParams memory exactInputParams = ISwapRouter.ExactInputParams({
            path : path,
            recipient : data.exitInETH ? address(0) : data.receiver,
            deadline : block.timestamp + 10000,
            amountIn : data.amount,
            amountOutMinimum : amountOutMinimum
        });

        if(data.enterInETH || data.exitInETH) {
            return _swapLiquidityMulticall(data.enterInETH, data.exitInETH, data.amount, data.receiver, abi.encodeWithSelector(ISwapRouter(_uniswapV3SwapRouterAddress).exactInput.selector, exactInputParams));
        }
        return ISwapRouter(_uniswapV3SwapRouterAddress).exactInput(exactInputParams);
    }

    function _swapLiquidityMulticall(bool enterInETH, bool exitInETH, uint256 value, address recipient, bytes memory data) private returns (uint256) {
        bytes[] memory multicall = new bytes[](enterInETH && exitInETH ? 3 : 2);
        multicall[0] = data;
        if(enterInETH && exitInETH) {
            multicall[1] = abi.encodeWithSelector(IPeripheryPayments(address(0)).refundETH.selector);
            multicall[2] = abi.encodeWithSelector(IPeripheryPayments(address(0)).unwrapWETH9.selector, 0, recipient);
        } else {
            multicall[1] = enterInETH ? abi.encodeWithSelector(IPeripheryPayments(address(0)).refundETH.selector) : abi.encodeWithSelector(IPeripheryPayments(_uniswapV3SwapRouterAddress).unwrapWETH9.selector, 0, recipient);
        }
        return abi.decode(IMulticall(address(0)).multicall{value : enterInETH ? value : 0}(multicall)[0], (uint256));
    }

    function _checkMinAmounts(uint256[] memory amounts, uint256[] memory minAmounts) private pure {
        for(uint256 i = 0; i < amounts.length; i++) {
            _checkMinAmount(amounts[i], minAmounts[i]);
        }
    }

    function _checkMinAmount(uint256 amount, uint256 minAmount) private pure {
        require(amount >= minAmount, "too little received");
    }
}