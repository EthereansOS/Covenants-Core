//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./FixedInflationData.sol";
import "./IFixedInflationExtension.sol";
import "./util/IERC20.sol";
import "../amm-aggregator/common/IAMM.sol";
import "./IFixedInflation.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IPeripheryPayments.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import "@ethereansos/swissknife/contracts/environment/ethereum/BlockRetriever.sol";

contract FixedInflationUniV3 is IFixedInflation, BlockRetriever {

    event Executed(bool);

    uint256 public constant ONE_HUNDRED = 1e18;

    address public initializer;

    mapping(address => uint256) private _tokenIndex;
    address[] private _tokensToTransfer;
    uint256[] private _tokenTotalSupply;
    uint256[] private _tokenAmounts;
    uint256[] private _tokenMintAmounts;
    uint256[] private _tokenBalanceOfBefore;

    address public host;

    FixedInflationEntry private _entry;
    FixedInflationOperation[] private _operations;

    address private UNISWAP_V3_SWAP_ROUTER_ADDRESS;
    address private ETHEREUM_ADDRESS;

    function lazyInit(bytes memory lazyInitData) public returns(bytes memory extensionInitResult) {

        require(initializer == address(0), "Already init");
        initializer = msg.sender;

        address uniswapV3SwapRouterAddress;
        address extension;
        (uniswapV3SwapRouterAddress, extension, lazyInitData) = abi.decode(lazyInitData, (address, address, bytes));
        require((host = extension) != address(0), "extension");

        ETHEREUM_ADDRESS = IPeripheryImmutableState(UNISWAP_V3_SWAP_ROUTER_ADDRESS = uniswapV3SwapRouterAddress).WETH9();

        (bytes memory extensionPayload, FixedInflationEntry memory newEntry, FixedInflationOperation[] memory newOperations) = abi.decode(lazyInitData, (bytes, FixedInflationEntry, FixedInflationOperation[]));

        if(keccak256(extensionPayload) != keccak256("")) {
            extensionInitResult = _call(_host, extensionPayload);
        }
        _set(newEntry, newOperations);
    }

    receive() external payable {
    }

    modifier extensionOnly() {
        require(msg.sender == host, "Unauthorized");
        _;
    }

    modifier activeExtensionOnly() {
        require(IFixedInflationExtension(host).active(), "not active host");
        _;
    }

    function entry() public view returns(FixedInflationEntry memory, FixedInflationOperation[] memory) {
        return (_entry, _operations);
    }

    function setEntry(FixedInflationEntry memory newEntry, FixedInflationOperation[] memory newOperations) public override extensionOnly {
        _set(newEntry, newOperations);
    }

    function nextBlock() public view returns(uint256) {
        return _entry.lastBlock == 0 ? _blockNumber() : (_entry.lastBlock + _entry.blockInterval);
    }

    function flushBack(address[] memory tokenAddresses) public override extensionOnly {
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            _transferTo(tokenAddresses[i], host, _balanceOf(tokenAddresses[i]));
        }
    }

    function execute(bool earnByAmounts) public activeExtensionOnly returns(bool executed) {
        (executed,) = executeWithMinAmounts(earnByAmounts, new uint256[](0));
    }

    function executeWithMinAmounts(bool earnByAmounts, uint256[] memory minAmounts) public activeExtensionOnly returns(bool executed, uint256[] memory outputAmounts) {
        require(_blockNumber() >= nextBlock(), "Too early to execute");
        require(_operations.length > 0, "No operations");
        emit Executed(executed = _ensureExecute());
        if(executed) {
            _entry.lastBlock = _blockNumber();
            outputAmounts = _execute(earnByAmounts, msg.sender, minAmounts);
        } else {
            try IFixedInflationExtension(host).deactivationByFailure() {
            } catch {
            }
        }
        _clearVars();
    }

    function _ensureExecute() private returns(bool) {
        _collectFixedInflationOperationsTokens();
        try IFixedInflationExtension(host).receiveTokens(_tokensToTransfer, _tokenAmounts, _tokenMintAmounts) {
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

    function _execute(bool earnByInput, address rewardReceiver, uint256[] memory minAmounts) private returns (uint256[] memory outputAmounts) {
        outputAmounts = new uint256[](_operations.length);
        for(uint256 i = 0 ; i < _operations.length; i++) {
            FixedInflationOperation memory operation = _operations[i];
            uint256 amountIn = _calculateTokenAmount(operation.inputTokenAddress, operation.inputTokenAmount, operation.inputTokenAmountIsPercentage);
            if(operation.ammPlugin == address(0)) {
                outputAmounts[i] = _transferTo(operation.inputTokenAddress, amountIn, rewardReceiver, _entry.callerRewardPercentage, operation);
            } else {
                outputAmounts[i] = _swap(operation, amountIn, i < minAmounts.length ? minAmounts[i] : 0, rewardReceiver, _entry.callerRewardPercentage, earnByInput);
            }
        }
    }

    function _swap(FixedInflationOperation memory operation, uint256 amountIn, uint256 minAmount, address rewardReceiver, uint256 callerRewardPercentage, bool earnByInput) private returns(uint256 outputAmount) {

        uint256 inputReward = earnByInput ? _calculateRewardPercentage(amountIn, callerRewardPercentage) : 0;

        address ethereumAddress = ETHEREUM_ADDRESS;
        if(operation.ammPlugin != UNISWAP_V3_SWAP_ROUTER_ADDRESS) {
            (ethereumAddress,,) = IAMM(operation.ammPlugin).data();
        }

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

        outputAmount = operation.ammPlugin == UNISWAP_V3_SWAP_ROUTER_ADDRESS ? _swapLiquidityUniswapV3(swapData, minAmount) : IAMM(operation.ammPlugin).swapLiquidity{value : swapData.enterInETH ? amountIn : 0}(swapData);

        require(outputAmount >= minAmount, "slippage");

        if(earnByInput) {
            _transferTo(operation.enterInETH ? address(0) : operation.inputTokenAddress, rewardReceiver, inputReward);
        }
        _transferTo(operation.exitInETH ? address(0) : outputToken, outputAmount, earnByInput ? address(0) : rewardReceiver, earnByInput ? 0 : callerRewardPercentage, operation);
    }

    function _calculateRewardPercentage(uint256 totalAmount, uint256 rewardPercentage) private pure returns (uint256) {
        return (totalAmount * ((rewardPercentage * 1e18) / ONE_HUNDRED)) / 1e18;
    }

    function _transferTo(address erc20TokenAddress, uint256 totalAmount, address rewardReceiver, uint256 callerRewardPercentage, FixedInflationOperation memory operation) private returns(uint256 outputAmount) {
        outputAmount = totalAmount;
        uint256 availableAmount = totalAmount;

        uint256 currentPartialAmount = rewardReceiver == address(0) ? 0 : _calculateRewardPercentage(availableAmount, callerRewardPercentage);
        _transferTo(erc20TokenAddress, rewardReceiver, currentPartialAmount);
        availableAmount -= currentPartialAmount;

        IFixedInflationFactory fixedInflationFactory = IFixedInflationFactory(initializer);
        address factoryOfFactoriesAddress = fixedInflationFactory.initializer();
        if(erc20TokenAddress != address(0)) {
            _safeApprove(erc20TokenAddress, factoryOfFactoriesAddress, availableAmount);
        }
        currentPartialAmount = fixedInflationFactory.payFee{value : erc20TokenAddress != address(0) ? 0 : availableAmount}(address(this), erc20TokenAddress, availableAmount, "");
        availableAmount -= currentPartialAmount;

        if(erc20TokenAddress != address(0)) {
            _safeApprove(erc20TokenAddress, factoryOfFactoriesAddress, 0);
        }

        uint256 stillAvailableAmount = availableAmount;

        for(uint256 i = 0; i < operation.receivers.length - 1; i++) {
            _transferTo(erc20TokenAddress, operation.receivers[i], currentPartialAmount = _calculateRewardPercentage(stillAvailableAmount, operation.receiversPercentages[i]));
            availableAmount -= currentPartialAmount;
        }

        _transferTo(erc20TokenAddress, operation.receivers[operation.receivers.length - 1], availableAmount);
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
            _safeApprove(erc20TokenAddress, host, value);
            IFixedInflationExtension(host).burnToken(erc20TokenAddress, value);
        }
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
            }
            require(percentage < ONE_HUNDRED, "More than one hundred");
            _operations.push(operation);
        }
    }

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

    function _swapLiquidityUniswapV3(SwapData memory data, uint256 amountOutMinimum) private returns(uint256) {
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
            return _swapLiquidityMulticall(data.enterInETH, data.exitInETH, data.amount, data.receiver, abi.encodeWithSelector(ISwapRouter(UNISWAP_V3_SWAP_ROUTER_ADDRESS).exactInput.selector, exactInputParams));
        }
        return ISwapRouter(UNISWAP_V3_SWAP_ROUTER_ADDRESS).exactInput(exactInputParams);
    }

    function _swapLiquidityMulticall(bool enterInETH, bool exitInETH, uint256 value, address recipient, bytes memory data) private returns (uint256) {
        bytes[] memory multicall = new bytes[](enterInETH && exitInETH ? 3 : 2);
        multicall[0] = data;
        if(enterInETH && exitInETH) {
            multicall[1] = abi.encodeWithSelector(IPeripheryPayments(UNISWAP_V3_SWAP_ROUTER_ADDRESS).refundETH.selector);
            multicall[2] = abi.encodeWithSelector(IPeripheryPayments(UNISWAP_V3_SWAP_ROUTER_ADDRESS).unwrapWETH9.selector, 0, recipient);
        } else {
            multicall[1] = enterInETH ? abi.encodeWithSelector(IPeripheryPayments(UNISWAP_V3_SWAP_ROUTER_ADDRESS).refundETH.selector) : abi.encodeWithSelector(IPeripheryPayments(UNISWAP_V3_SWAP_ROUTER_ADDRESS).unwrapWETH9.selector, 0, recipient);
        }
        return abi.decode(IMulticall(UNISWAP_V3_SWAP_ROUTER_ADDRESS).multicall{value : enterInETH ? value : 0}(multicall)[0], (uint256));
    }
}

interface IFixedInflationFactory {
    function initializer() external view returns (address);
    function payFee(address sender, address tokenAddress, uint256 value, bytes calldata permitSignature) external payable returns (uint256 feePaid);
}