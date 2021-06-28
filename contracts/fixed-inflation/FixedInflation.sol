//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./FixedInflationData.sol";
import "./IFixedInflationExtension.sol";
import "./util/IERC20.sol";
import "../amm-aggregator/common/IAMM.sol";
import "./IFixedInflationFactory.sol";
import "./IFixedInflation.sol";

contract FixedInflation is IFixedInflation {

    event Executed(bool);

    uint256 public constant ONE_HUNDRED = 1e18;

    address public _factory;

    mapping(address => uint256) private _tokenIndex;
    address[] private _tokensToTransfer;
    uint256[] private _tokenTotalSupply;
    uint256[] private _tokenAmounts;
    uint256[] private _tokenMintAmounts;
    uint256[] private _tokenBalanceOfBefore;

    address public extension;

    FixedInflationEntry private _entry;
    FixedInflationOperation[] private _operations;

    function init(address _extension, bytes memory extensionPayload, FixedInflationEntry memory newEntry, FixedInflationOperation[] memory newOperations) public returns(bytes memory extensionInitResult) {
        require(_factory == address(0), "Already init");
        require(_extension != address(0), "Blank extension");
        _factory = msg.sender;
        extension = _extension;
        if(_extension == address(0)) {
            _extension = _clone(IFixedInflationFactory(_factory).fixedInflationDefaultExtension());
        }
        if(keccak256(extensionPayload) != keccak256("")) {
            extensionInitResult = _call(_extension, extensionPayload);
        }
        _set(newEntry, newOperations);
    }

    receive() external payable {
    }

    modifier extensionOnly() {
        require(msg.sender == extension, "Unauthorized");
        _;
    }

    modifier activeExtensionOnly() {
        require(IFixedInflationExtension(extension).active(), "not active extension");
        _;
    }

    function entry() public view returns(FixedInflationEntry memory, FixedInflationOperation[] memory) {
        return (_entry, _operations);
    }

    function setEntry(FixedInflationEntry memory newEntry, FixedInflationOperation[] memory newOperations) public override extensionOnly {
        _set(newEntry, newOperations);
    }

    function nextBlock() public view returns(uint256) {
        return _entry.lastBlock == 0 ? block.number : (_entry.lastBlock + _entry.blockInterval);
    }

    function flushBack(address[] memory tokenAddresses) public override extensionOnly {
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            _transferTo(tokenAddresses[i], extension, _balanceOf(tokenAddresses[i]));
        }
    }

    function execute(bool earnByAmounts) public activeExtensionOnly returns(bool executed) {
        require(block.number >= nextBlock(), "Too early to execute");
        require(_operations.length > 0, "No operations");
        emit Executed(executed = _ensureExecute());
        if(executed) {
            _entry.lastBlock = block.number;
            _execute(earnByAmounts, msg.sender);
        } else {
            try IFixedInflationExtension(extension).deactivationByFailure() {
            } catch {
            }
        }
        _clearVars();
    }

    function _ensureExecute() private returns(bool) {
        _collectFixedInflationOperationsTokens();
        try IFixedInflationExtension(extension).receiveTokens(_tokensToTransfer, _tokenAmounts, _tokenMintAmounts) {
        } catch {
            return false;
        }
        for(uint256 i = 0; i < _tokensToTransfer.length; i++) {
            if(_balanceOf(_tokensToTransfer[i]) != (_tokenBalanceOfBefore[i] + _tokenAmounts[i] + _tokenMintAmounts[i])) {
                return false;
            }
        }
        return true;
    }

    function _collectFixedInflationOperationsTokens() private {
        for(uint256 i = 0; i < _operations.length; i++) {
            FixedInflationOperation memory operation = _operations[i];
            _collectTokenData(operation.ammPlugin != address(0) && operation.enterInETH ? address(0) : operation.inputTokenAddress, operation.inputTokenAmount, operation.inputTokenAmountIsPercentage, operation.inputTokenAmountIsByMint);
        }
    }

    function _collectTokenData(address inputTokenAddress, uint256 inputTokenAmount, bool inputTokenAmountIsPercentage, bool inputTokenAmountIsByMint) private {
        if(inputTokenAmount == 0) {
            return;
        }

        uint256 position = _tokenIndex[inputTokenAddress];

        if(_tokensToTransfer.length == 0 || _tokensToTransfer[position] != inputTokenAddress) {
            _tokenIndex[inputTokenAddress] = (position = _tokensToTransfer.length);
            _tokensToTransfer.push(inputTokenAddress);
            _tokenAmounts.push(0);
            _tokenMintAmounts.push(0);
            _tokenBalanceOfBefore.push(_balanceOf(inputTokenAddress));
            _tokenTotalSupply.push(0);
        }
        uint256 amount = _calculateTokenAmount(inputTokenAddress, inputTokenAmount, inputTokenAmountIsPercentage);
        if(inputTokenAmountIsByMint) {
            _tokenMintAmounts[position] = _tokenMintAmounts[position] + amount;
        } else {
            _tokenAmounts[position] = _tokenAmounts[position] + amount;
        }
    }

    function _balanceOf(address tokenAddress) private view returns (uint256) {
        if(tokenAddress == address(0)) {
            return address(this).balance;
        }
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function _calculateTokenAmount(address tokenAddress, uint256 tokenAmount, bool tokenAmountIsPercentage) private returns(uint256) {
        if(!tokenAmountIsPercentage) {
            return tokenAmount;
        }
        uint256 tokenIndex = _tokenIndex[tokenAddress];
        _tokenTotalSupply[tokenIndex] = _tokenTotalSupply[tokenIndex] != 0 ? _tokenTotalSupply[tokenIndex] : IERC20(tokenAddress).totalSupply();
        return (_tokenTotalSupply[tokenIndex] * ((tokenAmount * 1e18) / ONE_HUNDRED)) / 1e18;
    }

    function _clearVars() private {
        for(uint256 i = 0; i < _tokensToTransfer.length; i++) {
            delete _tokenIndex[_tokensToTransfer[i]];
        }
        delete _tokensToTransfer;
        delete _tokenTotalSupply;
        delete _tokenAmounts;
        delete _tokenMintAmounts;
        delete _tokenBalanceOfBefore;
    }

    function _execute(bool earnByInput, address rewardReceiver) private {
        for(uint256 i = 0 ; i < _operations.length; i++) {
            FixedInflationOperation memory operation = _operations[i];
            uint256 amountIn = _calculateTokenAmount(operation.inputTokenAddress, operation.inputTokenAmount, operation.inputTokenAmountIsPercentage);
            if(operation.ammPlugin == address(0)) {
                _transferTo(operation.inputTokenAddress, amountIn, rewardReceiver, _entry.callerRewardPercentage, operation.receivers, operation.receiversPercentages);
            } else {
                _swap(operation, amountIn, rewardReceiver, _entry.callerRewardPercentage, earnByInput);
            }
        }
    }

    function _swap(FixedInflationOperation memory operation, uint256 amountIn, address rewardReceiver, uint256 callerRewardPercentage, bool earnByInput) private {

        uint256 inputReward = earnByInput ? _calculateRewardPercentage(amountIn, callerRewardPercentage) : 0;

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
            amountIn - inputReward,
            address(this)
        );

        if(swapData.inputToken != address(0) && !swapData.enterInETH) {
            _safeApprove(swapData.inputToken, operation.ammPlugin, swapData.amount);
        }

        uint256 amountOut;
        if(swapData.enterInETH) {
            amountOut = IAMM(operation.ammPlugin).swapLiquidity{value : amountIn}(swapData);
        } else {
            amountOut = IAMM(operation.ammPlugin).swapLiquidity(swapData);
        }

        if(earnByInput) {
            _transferTo(operation.enterInETH ? address(0) : operation.inputTokenAddress, rewardReceiver, inputReward);
        }
        _transferTo(operation.exitInETH ? address(0) : outputToken, amountOut, earnByInput ? address(0) : rewardReceiver, earnByInput ? 0 : callerRewardPercentage, operation.receivers, operation.receiversPercentages);
    }

    function _calculateRewardPercentage(uint256 totalAmount, uint256 rewardPercentage) private pure returns (uint256) {
        return (totalAmount * ((rewardPercentage * 1e18) / ONE_HUNDRED)) / 1e18;
    }

    function _transferTo(address erc20TokenAddress, uint256 totalAmount, address rewardReceiver, uint256 callerRewardPercentage, address[] memory receivers, uint256[] memory receiversPercentages) private {
        uint256 availableAmount = totalAmount;

        uint256 currentPartialAmount = rewardReceiver == address(0) ? 0 : _calculateRewardPercentage(availableAmount, callerRewardPercentage);
        _transferTo(erc20TokenAddress, rewardReceiver, currentPartialAmount);
        availableAmount -= currentPartialAmount;

        (uint256 dfoFeePercentage, address dfoWallet) = IFixedInflationFactory(_factory).feePercentageInfo();
        currentPartialAmount = dfoFeePercentage == 0 || dfoWallet == address(0) ? 0 : _calculateRewardPercentage(availableAmount, dfoFeePercentage);
        _transferTo(erc20TokenAddress, dfoWallet, currentPartialAmount);
        availableAmount -= currentPartialAmount;

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
        _safeTransfer(erc20TokenAddress, to, value);
    }

    function _safeApprove(address erc20TokenAddress, address to, uint256 value) internal {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).approve.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'APPROVE_FAILED');
    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) private {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFER_FAILED');
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

    function _set(FixedInflationEntry memory fixedInflationEntry, FixedInflationOperation[] memory operations) private {
        require(keccak256(bytes(fixedInflationEntry.name)) != keccak256(""), "Name");
        require(fixedInflationEntry.blockInterval > 0, "Interval");
        require(fixedInflationEntry.callerRewardPercentage < ONE_HUNDRED, "Percentage");
        _entry = fixedInflationEntry;
        _setOperations(operations);
    }

    function _setOperations(FixedInflationOperation[] memory operations) private {
        delete _operations;
        for(uint256 i = 0; i < operations.length; i++) {
            FixedInflationOperation memory operation = operations[i];
            require(operation.receivers.length > 0, "No receivers");
            require(operation.receiversPercentages.length == (operation.receivers.length - 1), "Last receiver percentage is calculated automatically");
            uint256 percentage = 0;
            for(uint256 j = 0; j < operation.receivers.length - 1; j++) {
                percentage += operation.receiversPercentages[j];
                require(operation.receivers[j] != address(0), "Void receiver");
            }
            require(operation.receivers[operation.receivers.length - 1] != address(0), "Void receiver");
            require(percentage < ONE_HUNDRED, "More than one hundred");
            _operations.push(operation);
        }
    }

    /** @dev clones the input contract address and returns the copied contract address.
     * @param original address of the original contract.
     * @return copy copied contract address.
     */
    function _clone(address original) private returns (address copy) {
        assembly {
            mstore(
                0,
                or(
                    0x5880730000000000000000000000000000000000000000803b80938091923cF3,
                    mul(original, 0x1000000000000000000)
                )
            )
            copy := create(0, 0, 32)
            switch extcodesize(copy)
                case 0 {
                    invalid()
                }
        }
    }
}