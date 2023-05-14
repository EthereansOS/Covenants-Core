//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/IRoutinesExtension.sol";
import "@ethereansos/swissknife/contracts/generic/impl/LazyInitCapableElement.sol";
import { IERC20Full, TransferUtilities } from "@ethereansos/swissknife/contracts/lib/GeneralUtilities.sol";
import "../../amm-aggregator/model/IAMMAggregator.sol";
import "../../util/uniswapV3/IUniswapV3Pool.sol";
import "../../util/uniswapV3/ISwapRouter.sol";
import "../../util/uniswapV3/IMulticall.sol";
import "../../util/uniswapV3/IPeripheryPayments.sol";
import "../../util/uniswapV3/IPeripheryImmutableState.sol";
import "../../util/INONGovRules.sol";

contract Routines is IRoutines, LazyInitCapableElement {
    using TransferUtilities for address;

    uint256 private constant ONE_HUNDRED = 1e18;

    address private _ammAggregatorAddress;
    RoutinesEntry private _entry;
    RoutinesOperation[] private _operations;

    mapping(address => uint256) private _totalSupply;

    constructor(bytes memory lazyInitData) LazyInitCapableElement(lazyInitData) {}

    function _lazyInit(bytes memory lazyInitData) internal override returns(bytes memory lazyInitResponse) {
        address _host = host;
        require(_host != address(0), "host");

        (_ammAggregatorAddress, lazyInitData) = abi.decode(lazyInitData, (address, bytes));

        RoutinesEntry memory newEntry;
        RoutinesOperation[] memory newOperations;
        (lazyInitData, newEntry, newOperations) = abi.decode(lazyInitData, (bytes, RoutinesEntry, RoutinesOperation[]));

        if(keccak256(lazyInitData) != keccak256("")) {
            lazyInitResponse = ILazyInitCapableElement(_host).lazyInit(lazyInitData);
        }
        _set(newEntry, newOperations);
    }

    function _supportsInterface(bytes4 selector) internal override view returns(bool) {
    }

    receive() external payable {}

    function entry() external view returns(RoutinesEntry memory, RoutinesOperation[] memory) {
        return (_entry, _operations);
    }

    function setEntry(RoutinesEntry memory newEntry, RoutinesOperation[] memory newOperations) external override authorizedOnly {
        _set(newEntry, newOperations);
    }

    function flushBack(address[] memory tokenAddresses) external override authorizedOnly {
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            _transferTo(tokenAddresses[i], host, tokenAddresses[i].balanceOf(address(this)));
        }
    }

    function nextEvent() public view returns(uint256) {
        return _entry.lastEvent == 0 ? block.timestamp : (_entry.lastEvent + _entry.eventInterval);
    }

    function execute(bool earnByAmounts, address rewardReceiver, uint256[] memory amountsMin) external override returns(bool executed, uint256[] memory outputAmounts) {
        require(block.timestamp >= nextEvent(), "Too early to execute");
        require(_operations.length > 0, "No operations");
        require(IRoutinesExtension(host).active(), "not active host");
        uint256[] memory amountsIn = _tryRetrieveAmountsIn();
        emit Executed(executed = amountsIn.length != 0);
        if(executed) {
            _entry.lastEvent = block.timestamp;
            outputAmounts = _execute(earnByAmounts, rewardReceiver != address(0) ? rewardReceiver : msg.sender, amountsIn, amountsMin);
        } else {
            try IRoutinesExtension(host).deactivationByFailure() {
            } catch {
            }
        }
    }

    function _tryRetrieveAmountsIn() private returns(uint256[] memory amountsIn) {
        (address[] memory tokenAddresses, uint256[] memory amounts, bool[] memory amountIsByMint) = _calculateRoutinesOperationsTokensAmounts();
        amountsIn = new uint256[](amounts.length);
        for(uint256 i = 0; i < amountsIn.length; i++) {
            if(amountIsByMint[i]) {
                amountsIn[i] = amounts[i];
                amounts[i] = 0;
            }
        }
        try IRoutinesExtension(host).sendAndMintTokens(tokenAddresses, amounts, amountsIn) returns(uint256[] memory transferredAmounts, uint256[] memory mintedAmounts) {
            for(uint256 i = 0; i < transferredAmounts.length; i++) {
                amountsIn[i] = transferredAmounts[i] != 0 ? transferredAmounts[i] : mintedAmounts[i];
            }
        } catch {
            amountsIn = new uint256[](0);
        }
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            delete _totalSupply[tokenAddresses[i]];
        }
    }

    function _calculateRoutinesOperationsTokensAmounts() private returns(address[] memory tokenAddresses, uint256[] memory amounts, bool[] memory amountIsByMint) {
        tokenAddresses = new address[](_operations.length);
        amounts = new uint256[](tokenAddresses.length);
        amountIsByMint = new bool[](tokenAddresses.length);
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            RoutinesOperation memory operation = _operations[i];
            amountIsByMint[i] = operation.inputTokenAmountIsByMint;
            amounts[i] = _calculateAmount(tokenAddresses[i] = operation.ammPlugin != address(0) && operation.enterInETH ? address(0) : operation.inputTokenAddress, operation.inputTokenAmount, operation.inputTokenAmountIsPercentage);
        }
    }

    function _calculateAmount(address inputTokenAddress, uint256 inputTokenAmount, bool inputTokenAmountIsPercentage) private returns (uint256) {
        if(inputTokenAmount == 0 || !inputTokenAmountIsPercentage) {
            return inputTokenAmount;
        }

        uint256 totalSupply = _totalSupply[inputTokenAddress];
        if(totalSupply == 0) {
            totalSupply = _totalSupply[inputTokenAddress] = IERC20Full(inputTokenAddress).totalSupply();
        }

        return _calculatePercentage(totalSupply, inputTokenAmount);
    }

    function _execute(bool earnByInput, address rewardReceiver, uint256[] memory amountsIn, uint256[] memory amountsMin) private returns (uint256[] memory outputAmounts) {
        outputAmounts = new uint256[](_operations.length);
        for(uint256 i = 0 ; i < _operations.length; i++) {
            RoutinesOperation memory operation = _operations[i];
            uint256 amountIn = amountsIn[i];
            if(operation.ammPlugin == address(0)) {
                outputAmounts[i] = _transferTo(operation.inputTokenAddress, amountIn, rewardReceiver, _entry.callerRewardPercentage, operation);
            } else {
                outputAmounts[i] = _swap(operation, amountIn, i < amountsMin.length ? amountsMin[i] : 0, rewardReceiver, _entry.callerRewardPercentage, earnByInput);
            }
        }
    }

    function _swap(RoutinesOperation memory operation, uint256 amountIn, uint256 minAmount, address rewardReceiver, uint256 callerRewardPercentage, bool earnByInput) private returns(uint256 outputAmount) {

        uint256 inputReward = earnByInput ? _calculatePercentage(amountIn, callerRewardPercentage) : 0;

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
            operation.enterInETH ? ethereumAddress : operation.inputTokenAddress,
            amountIn - inputReward,
            operation.additionalData,
            minAmount,
            address(this),
            block.timestamp + 1000
        );

        if(swapData.inputToken != address(0) && !swapData.enterInETH) {
            swapData.inputToken.safeApprove(operation.ammPlugin, swapData.amount);
        }

        outputAmount = IAMM(operation.ammPlugin).swap{value : swapData.enterInETH ? amountIn : 0}(swapData);

        require(outputAmount >= minAmount, "slippage");

        if(earnByInput) {
            _transferTo(operation.enterInETH ? address(0) : operation.inputTokenAddress, rewardReceiver, inputReward);
        }
        _transferTo(operation.exitInETH ? address(0) : outputToken, outputAmount, earnByInput ? address(0) : rewardReceiver, earnByInput ? 0 : callerRewardPercentage, operation);
    }

    function _calculatePercentage(uint256 value, uint256 percentage) private pure returns (uint256) {
        return (value * ((percentage * 1e18) / ONE_HUNDRED)) / 1e18;
    }

    function _transferTo(address erc20TokenAddress, uint256 totalAmount, address rewardReceiver, uint256 callerRewardPercentage, RoutinesOperation memory operation) private returns(uint256 outputAmount) {
        outputAmount = totalAmount;
        uint256 availableAmount = totalAmount;

        uint256 currentPartialAmount = rewardReceiver == address(0) ? 0 : _calculatePercentage(availableAmount, callerRewardPercentage);
        _transferTo(erc20TokenAddress, rewardReceiver, currentPartialAmount);
        availableAmount -= currentPartialAmount;

        INONGovRules routinesRules = INONGovRules(initializer);
        address routinesRulesInitializerAddress = routinesRules.initializer();
        erc20TokenAddress.safeApprove(routinesRulesInitializerAddress, availableAmount);
        currentPartialAmount = routinesRules.payFee{value : erc20TokenAddress != address(0) ? 0 : availableAmount}(address(this), erc20TokenAddress, availableAmount, "");
        erc20TokenAddress.safeApprove(routinesRulesInitializerAddress, 0);

        availableAmount -= currentPartialAmount;

        uint256 stillAvailableAmount = availableAmount;

        for(uint256 i = 0; i < operation.receivers.length - 1; i++) {
            _transferTo(erc20TokenAddress, operation.receivers[i], currentPartialAmount = _calculatePercentage(stillAvailableAmount, operation.receiversPercentages[i]));
            availableAmount -= currentPartialAmount;
        }

        _transferTo(erc20TokenAddress, operation.receivers[operation.receivers.length - 1], availableAmount);
    }

    function _transferTo(address erc20TokenAddress, address to, uint256 value) private {
        if(value == 0) {
            return;
        }
        if(erc20TokenAddress == address(0)) {
            erc20TokenAddress.safeTransfer(to, value);
        }
        if(to != address(0)) {
            erc20TokenAddress.safeTransfer(to, value);
        } else {
            erc20TokenAddress.safeApprove(host, value);
            IRoutinesExtension(host).burn(erc20TokenAddress, value);
        }
    }

    function _set(RoutinesEntry memory routinesEntry, RoutinesOperation[] memory operations) private {
        require(keccak256(bytes(routinesEntry.name)) != keccak256(""), "Name");
        require(routinesEntry.eventInterval > 0, "Interval");
        require(routinesEntry.callerRewardPercentage < ONE_HUNDRED, "Percentage");
        _entry = routinesEntry;
        _setOperations(operations);
    }

    function _setOperations(RoutinesOperation[] memory operations) private {
        delete _operations;
        address[] memory amms = IAMMAggregator(_ammAggregatorAddress).amms();
        for(uint256 i = 0; i < operations.length; i++) {
            RoutinesOperation memory operation = operations[i];
            _checkAMM(operation.ammPlugin, amms);
            require(operation.receivers.length > 0, "No receivers");
            require(operation.receiversPercentages.length == (operation.receivers.length - 1), "Last receiver percentage is calculated automatically");
            uint256 percentage = 0;
            for(uint256 j = 0; j < operation.receivers.length - 1; j++) {
                percentage += operation.receiversPercentages[j];
            }
            require(percentage < ONE_HUNDRED, "More than one hundred");
            _operations.push(operation);
        }
    }

    function _checkAMM(address ammPlugin, address[] memory amms) private pure {
        if(ammPlugin == address(0)) {
            return;
        }
        for(uint256 i = 0; i < amms.length; i++) {
            if(amms[i] == ammPlugin) {
                return;
            }
        }
        revert("Unknown AMM");
    }
}