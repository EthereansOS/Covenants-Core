//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/IPresto.sol";
import "../../amm-aggregator/model/IAMMAggregator.sol";
import { IERC20Full, TransferUtilities } from "@ethereansos/swissknife/contracts/lib/GeneralUtilities.sol";

contract Presto is IPresto {
    using TransferUtilities for address;

    struct AddLiquidityData {
        address ethereumAddress;
        address[] tokenAddresses;
        uint256[] amounts;
    }

    uint256 private constant ONE_HUNDRED = 1e18;

    address private immutable _ammAggregatorAddress;

    address[] private _tokensToTransfer;
    mapping(address => uint256) private _tokenIndex;

    mapping(uint256 => AddLiquidityData) private _addLiquidityData;

    constructor(address ammAggregatorAddress) {
        _ammAggregatorAddress = ammAggregatorAddress;
    }

    receive() external payable {
    }

    function execute(PrestoOperation[] memory operations) external override payable returns(uint256[] memory transferredAmounts, uint256[] memory outputAmounts) {
        (operations, transferredAmounts) = _collectTokens(operations);
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

    function _collectTokens(PrestoOperation[] memory operationsInput) private returns(PrestoOperation[] memory operations, uint256[] memory transferredAmounts) {
        uint256 ethAmount = 0;
        operations = new PrestoOperation[](operationsInput.length);
        transferredAmounts = new uint256[](operationsInput.length);
        address[] memory amms = IAMMAggregator(_ammAggregatorAddress).amms();
        for(uint256 i = 0; i < operationsInput.length; i++) {
            PrestoOperation memory operation = operationsInput[i];
            (address ethereumAddress, uint256 liquidityPoolTokenType) = (address(0), 0);
            if(operation.ammPlugin != address(0)) {
                (ethereumAddress, liquidityPoolTokenType) = _checkAMMAndRetrieveData(operation, amms);
            }
            if(operation.ammPlugin != address(0) && operation.liquidityPoolIds.length == 0) {
                require(liquidityPoolTokenType == 20, "ERC20");
                (uint256[] memory amounts, address[] memory tokensAddresses) = IAMM(operation.ammPlugin).byLiquidityPoolAmount(operation.liquidityPoolIdOrInputTokenAddress, operation.amount);
                bool hasEth = false;
                for(uint256 z = 0; z < tokensAddresses.length; z++) {
                    if(tokensAddresses[z] == ethereumAddress) {
                        hasEth = true;
                    }
                    uint256 _ethAmount;
                    (amounts[z], _ethAmount) = _collectTokenData(operation.enterInETH && tokensAddresses[z] == ethereumAddress ? address(0) : tokensAddresses[z], amounts[z]);
                    ethAmount += _ethAmount;
                }
                transferredAmounts[i] = amounts[0];
                require(!operation.enterInETH || hasEth, "Wrong use of enterInETH in addLiquidity");
                _addLiquidityData[i] = AddLiquidityData(ethereumAddress, tokensAddresses, amounts);
            } else {
                uint256 _ethAmount;
                (transferredAmounts[i], _ethAmount) = _collectTokenData(operation.ammPlugin != address(0) && operation.enterInETH ? address(0) : address(uint160(operation.liquidityPoolIdOrInputTokenAddress)), operation.amount);
                ethAmount += _ethAmount;
                operation.amount = transferredAmounts[i];
                operations[i] = operation;
            }
        }
        require(msg.value == ethAmount, "ETH");
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

    function _collectTokenData(address inputTokenAddress, uint256 inputTokenAmount) private returns (uint256 receivedAmount, uint256 ethAmount) {
        if(inputTokenAddress == address(0) || inputTokenAmount == 0) {
            return (inputTokenAmount, inputTokenAddress == address(0) ? inputTokenAmount : 0);
        }

        uint256 tokenIndex = _tokenIndex[inputTokenAddress];

        if(_tokensToTransfer.length == 0 || _tokensToTransfer[tokenIndex] != inputTokenAddress) {
            _tokenIndex[inputTokenAddress] = _tokensToTransfer.length;
            _tokensToTransfer.push(inputTokenAddress);
        }
        receivedAmount = inputTokenAddress.safeTransferFrom(msg.sender, address(this), inputTokenAmount);
    }

    function _flushAndClear() private {
        address[] memory tokensToTransfer = _tokensToTransfer;
        for(uint256 i = 0; i < tokensToTransfer.length; i++) {
            address tokenToTransfer = tokensToTransfer[i];
            tokenToTransfer.safeTransfer(msg.sender, tokenToTransfer.balanceOf(address(this)));
            delete _tokenIndex[tokenToTransfer];
        }
        address(0).safeTransfer(msg.sender, address(0).balanceOf(address(this)));
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
            address(0).safeTransfer(to, value);
            return;
        }
        if(to != address(0)) {
            erc20TokenAddress.safeTransfer(to, value);
            return;
        } else {
            erc20TokenAddress.safeBurn(value);
            return;
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