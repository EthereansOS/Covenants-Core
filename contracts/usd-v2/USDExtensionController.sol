//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma abicoder v2;

import "./USDExtension.sol";
import "./util/DFOHub.sol";
import "./util/ERC1155Receiver.sol";
import "./util/INativeV1.sol";
import "./util/IERC20WrapperV1.sol";
import "./util/IERC20.sol";
import "./AllowedAMM.sol";
import "../amm-aggregator/common/IAMM.sol";
import "../amm-aggregator/common/AMMData.sol";

contract USDExtensionController is ERC1155Receiver {

    uint256 public constant ONE_HUNDRED = 10000;

    uint256 private constant DECIMALS = 18;

    address private _doubleProxy;

    address private _extension;

    address private _collection;

    uint256 private _usdObjectId;
    address private _usdInteroperableInterfaceAddress;

    uint256 private _usdCreditObjectId;
    address private _usdCreditInteroperableInterfaceAddress;

    uint256 private _lastRedeemBlock;

    AllowedAMM[] private _allowedAMMs;

    uint256[] private _rebalanceByCreditPercentages;

    address[] private _rebalanceByCreditReceivers;

    uint256 private _rebalanceByCreditPercentageForCaller;

    constructor(address doubleProxyAddress,
        address[] memory rebalanceByCreditReceivers, uint256[] memory rebalanceByCreditPercentages, uint256 rebalanceByCreditPercentageForCaller, bytes memory allowedAMMsBytes) {
        _doubleProxy = doubleProxyAddress;
        _setRebalanceByCreditData(rebalanceByCreditReceivers, rebalanceByCreditPercentages, rebalanceByCreditPercentageForCaller);
        _setAllowedAMMs(allowedAMMsBytes);
    }

    receive() external payable {
    }

    function init(address orchestratorAddress,
        string calldata collectionName, string calldata collectionSymbol, string calldata collectionUri) public {
        require(_extension == address(0), "Init already called");
        USDExtension usdExtension = new USDExtension(orchestratorAddress, collectionName, collectionSymbol, collectionUri);
        _extension = address(usdExtension);
        _collection = usdExtension.collection();
    }

    function initUsdCollection(string calldata usdName, string calldata usdSymbol, string calldata usdUri) public {
        require(_usdInteroperableInterfaceAddress == address(0), "Init already called");
        USDExtension usdExtension = USDExtension(_extension);
        (_usdObjectId, _usdInteroperableInterfaceAddress) = usdExtension.mintEmpty(usdName, usdSymbol, usdUri, true);
    }

    function initCreditCollection(string calldata usdCreditName, string calldata usdCreditSymbol, string calldata usdCreditUri) public {
        require(_usdCreditInteroperableInterfaceAddress == address(0), "Init already called");
        USDExtension usdExtension = USDExtension(_extension);
        (_usdCreditObjectId, _usdCreditInteroperableInterfaceAddress) = usdExtension.mintEmpty(usdCreditName, usdCreditSymbol, usdCreditUri, true);
    }

    function init(address extensionAddress, uint256 usdObjectId, uint256 usdCreditObjectId) public {
        require(_extension == address(0), "Init already called");
        INativeV1 usdCollection = INativeV1(_collection = USDExtension(_extension = extensionAddress).collection());
        _usdInteroperableInterfaceAddress = address(usdCollection.asInteroperable(_usdObjectId = usdObjectId));
        _usdCreditInteroperableInterfaceAddress = address(usdCollection.asInteroperable(_usdCreditObjectId = usdCreditObjectId));
    }

    function _setRebalanceByCreditData(address[] memory rebalanceByCreditReceivers, uint256[] memory rebalanceByCreditPercentages, uint256 rebalanceByCreditPercentageForCaller) private {
        require(rebalanceByCreditReceivers.length > 0 && rebalanceByCreditReceivers.length == rebalanceByCreditPercentages.length, "Invalid lengths");
        uint256 percentage = rebalanceByCreditPercentageForCaller;
        for(uint256 i = 0; i < rebalanceByCreditReceivers.length; i++) {
            require(rebalanceByCreditReceivers[i] != address(0), "Void address");
            require(rebalanceByCreditPercentages[i] > 0, "Zero percentage");
            percentage += rebalanceByCreditPercentages[i];
        }
        require(percentage <= ONE_HUNDRED, "More than one hundred");
        _rebalanceByCreditPercentageForCaller = rebalanceByCreditPercentageForCaller;
        _rebalanceByCreditPercentages = rebalanceByCreditPercentages;
        _rebalanceByCreditReceivers = rebalanceByCreditReceivers;
    }

    function _setAllowedAMMs(bytes memory data) private {
        AllowedAMM[] memory amms = abi.decode(data, (AllowedAMM[]));
        delete _allowedAMMs;
        for(uint256 i = 0; i < amms.length; i++) {
            _allowedAMMs.push(amms[i]);
        }
    }

    function doubleProxy() public view returns (address) {
        return _doubleProxy;
    }

    function extension() public view returns (address) {
        return _extension;
    }

    function collection() public view returns (address) {
        return _collection;
    }

    function usdInfo() public view returns (address, uint256, address) {
        return (_collection, _usdObjectId, _usdInteroperableInterfaceAddress);
    }

    function usdCreditInfo() public view returns (address, uint256, address) {
        return (_collection, _usdCreditObjectId, _usdCreditInteroperableInterfaceAddress);
    }

    function rebalanceByCreditReceiversInfo() public view returns (address[] memory, uint256[] memory, uint256, address) {
        return (_rebalanceByCreditReceivers, _rebalanceByCreditPercentages, _rebalanceByCreditPercentageForCaller, IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDWalletAddress());
    }

    modifier byDFO virtual {
        require(_isFromDFO(msg.sender), "Unauthorized Action!");
        _;
    }

    function _isFromDFO(address sender) private view returns(bool) {
        return IMVDFunctionalitiesManager(IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDFunctionalitiesManagerAddress()).isAuthorizedFunctionality(sender);
    }

    function setDoubleProxy(address newDoubleProxy) public byDFO {
        _doubleProxy = newDoubleProxy;
    }

    function setRebalanceByCreditData(address[] memory rebalanceByCreditReceivers, uint256[] memory rebalanceByCreditPercentages, uint256 rebalanceByCreditPercentageForCaller) public byDFO {
        _setRebalanceByCreditData(rebalanceByCreditReceivers, rebalanceByCreditPercentages, rebalanceByCreditPercentageForCaller);
    }

    function changeController(address controller) public byDFO {
        USDExtension(_extension).setController(controller);
    }

    function setCollectionUri(string memory uri) public byDFO {
        USDExtension(_extension).setCollectionUri(uri);
    }

    function setItemUri(uint256 existingObjectId, string memory uri) public byDFO {
        USDExtension(_extension).setItemUri(existingObjectId, uri);
    }

    function setController(address newController) public byDFO {
        USDExtension(_extension).setController(newController);
    }

    function allowedAMMs() public view returns(AllowedAMM[] memory) {
        return _allowedAMMs;
    }

    function setAllowedAMMs(AllowedAMM[] memory newAllowedAMMs) public byDFO {
        _setAllowedAMMs(abi.encode(newAllowedAMMs));
    }

    function differences()
        public
        view
        returns (uint256 credit, uint256 debt)
    {
        uint256 totalSupply = INativeV1(_collection).totalSupply(_usdObjectId);
        uint256 effectiveAmount = 0;
        for(uint256 i = 0; i < _allowedAMMs.length; i++) {
            for(uint256 j = 0; j < _allowedAMMs[i].liquidityPools.length; j++) {
                effectiveAmount += _normalizeAndSumAmounts(i, j, 0);
            }
        }
        credit = effectiveAmount > totalSupply
            ? effectiveAmount - totalSupply
            : 0;
        debt = totalSupply > effectiveAmount
            ? totalSupply - effectiveAmount
            : 0;
    }

    function fromTokenToStable(address tokenAddress, uint256 amount)
        public
        view
        returns (uint256)
    {
        IERC20 token = IERC20(tokenAddress);
        uint256 tokenDecimals = token.decimals();
        uint256 remainingDecimals = DECIMALS - tokenDecimals;
        uint256 result = amount == 0 ? token.balanceOf(_extension) : amount;
        if (remainingDecimals == 0) {
            return result;
        }
        return result * 10**remainingDecimals;
    }

    function onERC1155Received(
        address,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    )
        public
        override
        returns(bytes4) {
            require(msg.sender == _collection, "Only uSD collection allowed here");
            _onSingleReceived(from, id, value, data);
            return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address from,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    )
        public
        override
        returns(bytes4) {

        require(msg.sender == _collection, "Only uSD collection allowed here");
        bytes[] memory payloads = abi.decode(data, (bytes[]));
        require(payloads.length == ids.length, "Wrong payloads length");
        for(uint256 i = 0; i < ids.length; i++) {
            _onSingleReceived(from, ids[i], values[i], payloads[i]);
        }
        return this.onERC1155BatchReceived.selector;
    }

    function _onSingleReceived(
        address from,
        uint256 id,
        uint256 value,
        bytes memory data) private {
            require(id == _usdObjectId, "Only uSD id allowed here");
            if(from == _extension) {
                return;
            }
            (uint256 action, bytes memory payload) = abi.decode(data, (uint256, bytes));
            if(action == 1) {
                _rebalanceByDebt(from, value);
            } else {
                _burn(from, value, payload);
            }
    }

    function _burn(address from, uint256 value, bytes memory payload) private {
        (uint256 ammPosition, uint256 liquidityPoolPosition, uint256 liquidityPoolAmount) = abi.decode(payload, (uint256, uint256, uint256));
        uint256 toBurn = _normalizeAndSumAmounts(ammPosition, liquidityPoolPosition, liquidityPoolAmount);
        require(value >= toBurn, "Insufficient Amount");
        if(value > toBurn) {
            INativeV1(_collection).safeTransferFrom(address(this), from, _usdObjectId, value - toBurn, "");
        }
        INativeV1(_collection).burn(_usdObjectId, toBurn);
        _removeLiquidity(from, ammPosition, liquidityPoolPosition, liquidityPoolAmount);
    }

    function _rebalanceByDebt(address from, uint256 value) private {
        (, uint256 debt) = differences();
        require(value <= debt, "Cannot Burn this amount");
        INativeV1(_collection).burn(_usdObjectId, value);
        USDExtension(_extension).mint(_usdCreditObjectId, value, from);
    }

    function rebalanceByCredit() public {
        require(
            block.number >=
            _lastRedeemBlock +
            IStateHolder(
                IMVDProxy(IDoubleProxy(_doubleProxy).proxy())
                    .getStateHolderAddress()
            )
                .getUint256("stablecoin.v2.rebalancebycredit.block.interval"),
            "Unauthorized action!"
        );
        _lastRedeemBlock = block.number;
        (uint256 credit, ) = differences();
        USDExtension(_extension).mint(_usdObjectId, credit, address(this));
        uint256 availableCredit = credit;
        uint256 reward = 0;
        if(_rebalanceByCreditPercentageForCaller > 0) {
            IERC20(_usdInteroperableInterfaceAddress).transfer(msg.sender, reward = _calculatePercentage(credit, _rebalanceByCreditPercentageForCaller));
            availableCredit -= reward;
        }
        for(uint256 i = 0; i < _rebalanceByCreditReceivers.length; i++) {
            IERC20(_usdInteroperableInterfaceAddress).transfer(_rebalanceByCreditReceivers[i], reward = _calculatePercentage(credit, _rebalanceByCreditPercentages[i]));
            availableCredit -= reward;
        }
        if(availableCredit > 0) {
            IERC20(_usdInteroperableInterfaceAddress).transfer(IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDWalletAddress(), availableCredit);
        }
    }

    function _calculatePercentage(uint256 total, uint256 percentage) private pure returns (uint256) {
        return (total * ((percentage * 1e18) / ONE_HUNDRED)) / 1e18;
    }

    modifier _forAllowedAMMAndLiquidityPool(uint256 ammIndex, uint256 liquidityPoolIndex) {
        require(
            ammIndex >= 0 && ammIndex < _allowedAMMs.length,
            "Unknown AMM!"
        );
        require(
            liquidityPoolIndex >= 0 && liquidityPoolIndex < _allowedAMMs[ammIndex].liquidityPools.length,
            "Unknown Liquidity Pool!"
        );
        _;
    }

    function addLiquidity(
        uint256 ammPosition,
        uint256 liquidityPoolPosition,
        uint256 liquidityPoolAmount
    )
        public
        _forAllowedAMMAndLiquidityPool(ammPosition, liquidityPoolPosition)
        returns(uint256 toMint)
    {
        IAMM amm = IAMM(_allowedAMMs[ammPosition].ammAddress);
        address liquidityPoolAddress = _allowedAMMs[ammPosition].liquidityPools[liquidityPoolPosition];
        uint256[] memory amounts = amm.byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount);
        address[] memory tokens = amm.tokens(liquidityPoolAddress);
        for(uint256 i = 0; i < tokens.length; i++) {
            _safeTransferFrom(tokens[i], msg.sender, address(this), amounts[i]);
            _safeApprove(tokens[i], address(amm), amounts[i]);
        }
        uint256[] memory spent;
        (toMint, spent) = IAMM(_allowedAMMs[ammPosition].ammAddress).addLiquidity(LiquidityPoolData(
            _allowedAMMs[ammPosition].liquidityPools[liquidityPoolPosition],
            liquidityPoolAmount,
            tokens,
            amounts,
            _extension
        ));
        USDExtension(_extension).mint(_usdObjectId, _normalizeAndSumAmounts(ammPosition, liquidityPoolPosition, toMint), msg.sender);
        for(uint256 i = 0; i < spent.length; i++) {
            uint256 difference = amounts[i] - spent[i];
            if(difference > 0) {
                _safeTransfer(tokens[i], msg.sender, difference);
            }
        }
    }

    function _removeLiquidity(
        address owner,
        uint256 ammPosition,
        uint256 liquidityPoolPosition,
        uint256 liquidityPoolAmount
    )
        private
        _forAllowedAMMAndLiquidityPool(ammPosition, liquidityPoolPosition)
    {
        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = _allowedAMMs[ammPosition].liquidityPools[liquidityPoolPosition];
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = liquidityPoolAmount;
        address[] memory receivers = new address[](1);
        receivers[0] = address(this);
        USDExtension(_extension).send(tokenAddresses, amounts, receivers);
        IAMM amm = IAMM(_allowedAMMs[ammPosition].ammAddress);
        _checkAllowance(_allowedAMMs[ammPosition].liquidityPools[liquidityPoolPosition], liquidityPoolAmount, _allowedAMMs[ammPosition].ammAddress);
        amm.removeLiquidity(LiquidityPoolData(
            _allowedAMMs[ammPosition].liquidityPools[liquidityPoolPosition],
            liquidityPoolAmount,
            amm.tokens(_allowedAMMs[ammPosition].liquidityPools[liquidityPoolPosition]),
            new uint256[](0),
            owner
        ));
    }

    function _normalizeAndSumAmounts(uint256 ammPosition, uint256 liquidityPoolPosition, uint256 liquidityPoolAmount)
        private
        view
        returns(uint256 amount) {
            IERC20 liquidityPool = IERC20(_allowedAMMs[ammPosition].liquidityPools[liquidityPoolPosition]);
            uint256[] memory amounts = IAMM(_allowedAMMs[ammPosition].ammAddress).byLiquidityPoolAmount(address(liquidityPool), liquidityPoolAmount != 0 ? liquidityPoolAmount : liquidityPool.balanceOf(_extension), DECIMALS);
            for(uint256 i = 0; i < amounts.length; i++) {
                amount += amounts[i];
            }
    }

    function _checkAllowance(address tokenAddress, uint256 value, address operator) internal virtual {
        if(tokenAddress == address(0) || operator == address(0)) {
            return;
        }
        IERC20 token = IERC20(tokenAddress);
        if(token.allowance(address(this), operator) <= value) {
            _safeApprove(tokenAddress, operator, token.totalSupply());
        }
    }

    function _safeApprove(address erc20TokenAddress, address to, uint256 value) internal virtual {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).approve.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'APPROVE_FAILED');
    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) internal virtual {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }

    function _safeTransferFrom(address erc20TokenAddress, address from, address to, uint256 value) internal virtual {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFERFROM_FAILED');
    }

    function _flushBack(address payable sender, address[] memory tokens) internal virtual {
        for(uint256 i = 0; i < tokens.length; i++) {
            if(tokens[i] != address(0)) {
                _flushBack(sender, tokens[i]);
            }
        }
        _flushBack(sender, address(0));
    }

    function _flushBack(address payable sender, address tokenAddress) internal virtual {
        uint256 balance = tokenAddress == address(0) ? address(this).balance : IERC20(tokenAddress).balanceOf(address(this));

        if(balance == 0) {
            return;
        }

        if(tokenAddress == address(0)) {
            return sender.transfer(balance);
        }
        _safeTransfer(tokenAddress, sender, balance);
    }
}