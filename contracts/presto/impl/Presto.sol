//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/IPresto.sol";
import "../../amm-aggregator/model/IAMMAggregator.sol";
import { IERC20Full, TransferUtilities } from "@ethereansos/swissknife/contracts/lib/GeneralUtilities.sol";


struct AddLiquidityData {
    address ethereumAddress;
    address[] tokenAddresses;
    uint256[] amounts;
}

contract Presto is IPresto {
    using TransferUtilities for address;

    uint256 private constant ONE_HUNDRED = 1e18;

    address[] private _tokensToTransfer;
    mapping(address => uint256) private _tokenAmounts;

    mapping(uint256 => AddLiquidityData) private _addLiquidityData;

    address private immutable _ammAggregator;

    constructor(address ammAggregator) {
        _ammAggregator = ammAggregator;
    }

    receive() external payable {
    }

    function execute(PrestoOperation[] memory operations) external override payable returns(uint256[] memory outputAmounts) {
        _transferToMe(operations);
        outputAmounts = new uint256[](operations.length);
        for(uint256 i = 0 ; i < operations.length; i++) {
            PrestoOperation memory operation = operations[i];
            require(block.timestamp < operation.deadline, "too late");
            if(operation.ammPlugin == address(0)) {
                outputAmounts[i] = operation.amount;
                _transferTo(address(uint160(operation.liquidityPoolIdOrInputTokenAddress)), operation.amount, operation.receivers, operation.receiversPercentages);
            } else if(operation.liquidityPoolIds.length == 0) {
                outputAmounts[i] = _addLiquidity(operation, i);
            } else {
                outputAmounts[i] = _swap(operation);
            }
        }
        _flushAndClear();
    }

    function _transferToMe(PrestoOperation[] memory operations) private {
        _collectTokens(operations);
        for(uint256 i = 0; i < _tokensToTransfer.length; i++) {
            address tokenAddress = _tokensToTransfer[i];
            uint256 amount = _tokenAmounts[tokenAddress];
            if(tokenAddress == address(0)) {
                require(msg.value == amount, "Incorrect ETH value");
            } else {
                tokenAddress.safeTransferFrom(msg.sender, address(this), amount);
            }
        }
    }

    function _collectTokens(PrestoOperation[] memory operations) private {
        address[] memory amms = IAMMAggregator(_ammAggregator).amms();
        for(uint256 i = 0; i < operations.length; i++) {
            PrestoOperation memory operation = operations[i];
            if(operation.ammPlugin != address(0) && operation.liquidityPoolIds.length == 0) {
                (address ethereumAddress, uint256 liquidityPoolTokenType) = _checkAMMAndRetrieveData(operation, amms);
                require(liquidityPoolTokenType == 20, "ERC20");
                (uint256[] memory amounts, address[] memory tokensAddresses) = IAMM(operation.ammPlugin).byLiquidityPoolAmount(operation.liquidityPoolIdOrInputTokenAddress, operation.amount);
                bool hasEth = false;
                for(uint256 z = 0; z < tokensAddresses.length; z++) {
                    if(tokensAddresses[z] == ethereumAddress) {
                        hasEth = true;
                    }
                    _collectTokenData(operation.enterInETH && tokensAddresses[z] == ethereumAddress ? address(0) : tokensAddresses[z], amounts[z]);
                }
                require(!operation.enterInETH || hasEth, "Wrong use of enterInETH in addLiquidity");
                _addLiquidityData[i] = AddLiquidityData(ethereumAddress, tokensAddresses, amounts);
            } else {
                _collectTokenData(operation.ammPlugin != address(0) && operation.enterInETH ? address(0) : address(uint160(operation.liquidityPoolIdOrInputTokenAddress)), operation.amount);
            }
        }
    }

    function _checkAMMAndRetrieveData(PrestoOperation memory operation, address[] memory amms) private view returns(address ethereumAddress, uint256 liquidityPoolTokenType) {
        if(operation.ammPlugin == address(0)) {
            return (address(0), 0);
        }
        address ammPlugin = operation.ammPlugin;
        for(uint256 i = 0; i < amms.length; i++) {
            if(amms[i] == ammPlugin) {
                (ethereumAddress,,, liquidityPoolTokenType,) = IAMM(ammPlugin).data();
                return (ethereumAddress, liquidityPoolTokenType);
            }
        }
        revert("Unknown AMM");
    }

    function _collectTokenData(address inputTokenAddress, uint256 inputTokenAmount) private {
        if(inputTokenAmount == 0) {
            return;
        }

        uint256 oldAmount = _tokenAmounts[inputTokenAddress];

        if(oldAmount == 0) {
            _tokensToTransfer.push(inputTokenAddress);
        }
        _tokenAmounts[inputTokenAddress] = oldAmount + inputTokenAmount;
    }

    function _flushAndClear() private {
        address[] memory tokensToTransfer = _tokensToTransfer;
        for(uint256 i = 0; i < tokensToTransfer.length; i++) {
            address tokenToTransfer = tokensToTransfer[i];
            tokenToTransfer.safeTransfer(msg.sender, tokenToTransfer.balanceOf(address(this)));
            delete _tokenAmounts[tokenToTransfer];
        }
        address(0).safeTransfer(msg.sender, address(0).balanceOf(address(this)));
        delete _tokenAmounts[address(0)];
        delete _tokensToTransfer;
    }

    function _addLiquidity(PrestoOperation memory operation, uint256 position) private returns (uint256 outputAmount) {
        AddLiquidityData memory addLiquidityData = _addLiquidityData[position];
        delete _addLiquidityData[position];
        uint256 value = 0;
        if(operation.enterInETH) {
            address[] memory tokenAddresses = addLiquidityData.tokenAddresses;
            for(uint256 i = 0; i < tokenAddresses.length; i++) {
                if(tokenAddresses[i] == addLiquidityData.ethereumAddress) {
                    value = addLiquidityData.amounts[i];
                    break;
                }
            }
        }
        LiquidityPoolParams memory liquidityPoolData = LiquidityPoolParams(
            operation.liquidityPoolIdOrInputTokenAddress,
            addLiquidityData.amounts[0],
            addLiquidityData.tokenAddresses[0],
            false,
            operation.enterInETH,
            operation.additionalData,
            operation.amountsMin,
            address(this),
            operation.deadline
        );
        uint256[] memory tokenAmounts;
        (outputAmount, tokenAmounts,,) = IAMM(operation.ammPlugin).addLiquidity{value : value}(liquidityPoolData);
        _checkAmountsMin(tokenAmounts, operation.amountsMin);
        _transferTo(address(uint160(operation.liquidityPoolIdOrInputTokenAddress)), outputAmount, operation.receivers, operation.receiversPercentages);
    }

    function _swap(PrestoOperation memory operation) private returns(uint256 outputAmount) {

        uint256 minAmount = operation.amountsMin.length > 0 ? operation.amountsMin[0] : 0;

        (address ethereumAddress,,,,) = IAMM(operation.ammPlugin).data();

        if(operation.exitInETH) {
            operation.swapPath[operation.swapPath.length - 1] = ethereumAddress;
        }

        address outputToken = operation.swapPath[operation.swapPath.length - 1];

        SwapParams memory swapData = SwapParams(
            operation.enterInETH,
            operation.exitInETH,
            operation.liquidityPoolIds,
            operation.swapPath,
            operation.enterInETH ? ethereumAddress : address(uint160(operation.liquidityPoolIdOrInputTokenAddress)),
            operation.amount,
            operation.additionalData,
            operation.amountsMin[0],
            address(this),
            operation.deadline
        );

        if(swapData.inputToken != address(0) && !swapData.enterInETH) {
            swapData.inputToken.safeApprove(operation.ammPlugin, swapData.amount);
        }

        outputAmount = IAMM(operation.ammPlugin).swap{value : swapData.enterInETH ? operation.amount : 0}(swapData);

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
            erc20TokenAddress.safeTransfer(to, value);
        } else {
            try IERC20Full(erc20TokenAddress).burn(value) {
            } catch {
                (bool result,) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20Full(address(0)).transfer.selector, address(0), value));
                if(!result) {
                    erc20TokenAddress.safeTransfer(0x000000000000000000000000000000000000dEaD, value);
                }
            }
        }
    }

    function _checkAmountsMin(uint256[] memory amounts, uint256[] memory amountsMin) private pure {
        for(uint256 i = 0; i < amounts.length; i++) {
            _checkMinAmount(amounts[i], amountsMin[i]);
        }
    }

    function _checkMinAmount(uint256 amount, uint256 minAmount) private pure {
        require(amount >= minAmount, "too little received");
    }
}