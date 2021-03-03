//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./IPresto.sol";
import "./util/IERC20.sol";
import "./util/DFOHub.sol";
import "../amm-aggregator/common/IAMM.sol";

contract Presto is IPresto {

    uint256 public override constant ONE_HUNDRED = 1e18;

    mapping(address => uint256) private _tokenIndex;
    address[] private _tokensToTransfer;
    uint256[] private _tokenAmounts;

    address public override doubleProxy;
    uint256 public override feePercentage;

    constructor(address _doubleProxy, uint256 _feePercentage) {
        doubleProxy = _doubleProxy;
        feePercentage = _feePercentage;
    }

    receive() external payable {
    }

    modifier onlyDFO() {
        require(IMVDFunctionalitiesManager(IMVDProxy(IDoubleProxy(doubleProxy).proxy()).getMVDFunctionalitiesManagerAddress()).isAuthorizedFunctionality(msg.sender), "Unauthorized.");
        _;
    }

    function feePercentageInfo() public override view returns (uint256, address) {
        return (feePercentage, IMVDProxy(IDoubleProxy(doubleProxy).proxy()).getMVDWalletAddress());
    }

    function setDoubleProxy(address _doubleProxy) public override onlyDFO {
        doubleProxy = _doubleProxy;
    }

    function setFeePercentage(uint256 _feePercentage) public override onlyDFO {
        feePercentage = _feePercentage;
    }

    function execute(PrestoOperation[] memory operations) public override payable {
        _transferToMe(operations);
        for(uint256 i = 0 ; i < operations.length; i++) {
            PrestoOperation memory operation = operations[i];
            if(operation.ammPlugin == address(0)) {
                _transferTo(operation.inputTokenAddress, operation.inputTokenAmount, operation.receivers, operation.receiversPercentages);
            } else if(operation.liquidityPoolAddresses.length == 0) {
                _addLiquidity(operation);
            } else {
                _swap(operation);
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
        for(uint256 i = 0; i < operations.length; i++) {
            PrestoOperation memory operation = operations[i];
            if(operation.ammPlugin != address(0) && operation.liquidityPoolAddresses.length == 0) {
                IAMM amm = IAMM(operation.ammPlugin);
                (address ethereumAddress,,) = (amm.data());
                (uint256[] memory amounts, address[] memory tokensAddresses) = amm.byLiquidityPoolAmount(operation.inputTokenAddress, operation.inputTokenAmount);
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

    function _addLiquidity(PrestoOperation memory operation) private {
        LiquidityPoolData memory liquidityPoolData = LiquidityPoolData(
            operation.inputTokenAddress,
            operation.inputTokenAmount,
            address(0),
            true,
            operation.enterInETH,
            address(this)
        );
        (uint256 amountOut,,) = IAMM(operation.ammPlugin).addLiquidity(liquidityPoolData);
        _transferTo(operation.inputTokenAddress, amountOut, operation.receivers, operation.receiversPercentages);
    }

    function _swap(PrestoOperation memory operation) private {

        (address ethereumAddress,,) = IAMM(operation.ammPlugin).data();

        if(operation.exitInETH) {
            operation.swapPath[operation.swapPath.length - 1] = ethereumAddress;
        }

        address outputToken = operation.swapPath[operation.swapPath.length - 1];

        SwapData memory swapData = SwapData(
            operation.enterInETH,
            operation.exitInETH,
            operation.liquidityPoolAddresses,
            operation.swapPath,
            operation.enterInETH ? ethereumAddress : operation.inputTokenAddress,
            operation.inputTokenAmount,
            address(this)
        );

        if(swapData.inputToken != address(0) && !swapData.enterInETH) {
            _safeApprove(swapData.inputToken, operation.ammPlugin, swapData.amount);
        }

        uint256 amountOut;
        if(swapData.enterInETH) {
            amountOut = IAMM(operation.ammPlugin).swapLiquidity{value : operation.inputTokenAmount}(swapData);
        } else {
            amountOut = IAMM(operation.ammPlugin).swapLiquidity(swapData);
        }
        _transferTo(operation.exitInETH ? address(0) : outputToken, amountOut, operation.receivers, operation.receiversPercentages);
    }

    function _calculateRewardPercentage(uint256 totalAmount, uint256 rewardPercentage) private pure returns (uint256) {
        return (totalAmount * ((rewardPercentage * 1e18) / ONE_HUNDRED)) / 1e18;
    }

    function _transferTo(address erc20TokenAddress, uint256 totalAmount, address[] memory receivers, uint256[] memory receiversPercentages) private {
        uint256 availableAmount = totalAmount;

        (uint256 dfoFeePercentage, address dfoWallet) = feePercentageInfo();
        uint256 currentPartialAmount = dfoFeePercentage == 0 || dfoWallet == address(0) ? 0 : _calculateRewardPercentage(availableAmount, dfoFeePercentage);
        _safeTransfer(erc20TokenAddress, dfoWallet, currentPartialAmount);
        availableAmount -= currentPartialAmount;

        uint256 stillAvailableAmount = availableAmount;

        for(uint256 i = 0; i < receivers.length - 1; i++) {
            _safeTransfer(erc20TokenAddress, receivers[i], currentPartialAmount = _calculateRewardPercentage(stillAvailableAmount, receiversPercentages[i]));
            availableAmount -= currentPartialAmount;
        }

        _safeTransfer(erc20TokenAddress, receivers[receivers.length - 1], availableAmount);
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
}