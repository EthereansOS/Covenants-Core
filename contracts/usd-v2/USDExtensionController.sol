//SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

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

    address private _doubleProxy;

    address private _extension;

    address private _collection;
    uint256 private _objectId;
    address private _interoperableInterfaceAddress;
    uint256 private _decimals;

    uint256 private _lastRedeemBlock;

    AllowedAMM[] private _allowedAMMs;

    uint256[] private _rebalanceByCreditMultipliers;

    address[] private _creditReceivers;

    constructor(address doubleProxyAddress,
        uint256[] memory rebalanceByCreditMultipliersInput, address[] memory creditReceiversInput, bytes memory allowedAMMsBytes) {
        _doubleProxy = doubleProxyAddress;
        
        _creditReceivers = creditReceiversInput;
        _rebalanceByCreditMultipliers = rebalanceByCreditMultipliersInput;
        _setAllowedAMMs(allowedAMMsBytes);
    }

    receive() external payable {
    }

    function init(address orchestratorAddress,
        string memory name, string memory symbol, string memory collectionUri, string memory itemUri) public {
        init(address(new USDExtension(orchestratorAddress, name, symbol, collectionUri, itemUri)));
    }

    function init(address extensionAddress) public {
        require(_extension == address(0), "Init already called");
        _extension = extensionAddress;
        (_collection, _objectId, _interoperableInterfaceAddress) = USDExtension(_extension).info();
        _decimals = INativeV1(_collection).decimals(_objectId);
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

    function objectId() public view returns (uint256) {
        return _objectId;
    }

    function interoperableInterface() public view returns (address) {
        return _interoperableInterfaceAddress;
    }

    function info() public view returns (address, uint256, address) {
        return (_collection, _objectId, _interoperableInterfaceAddress);
    }

    function creditReceivers() public view returns(address[] memory) {
        return _creditReceivers;
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

    function setCreditReceivers(address[] memory creditReceiversAddresses) public byDFO {
        _creditReceivers = creditReceiversAddresses;
    }

    function changeController(address controller) public byDFO {
        USDExtension(_extension).setController(controller);
    }

    function setCollectionUri(string memory uri) public byDFO {
        USDExtension(_extension).setCollectionUri(uri);
    }

    function setItemUri(string memory uri) public byDFO {
        USDExtension(_extension).setItemUri(uri);
    }

    function setController(address newController) public byDFO {
        USDExtension(_extension).setController(newController);
    }

    function flushToNewController(address[] memory tokenAddresses) public {
        address controller = USDExtension(_extension).controller();
        require(controller != address(this), "This is the last controller!");
        _flushBack(payable(controller), tokenAddresses);
    }

    function allowedAMMs() public view returns(AllowedAMM[] memory) {
        return _allowedAMMs;
    }

    function setAllowedAMMs(AllowedAMM[] memory newAllowedAMMs) public byDFO {
        _setAllowedAMMs(abi.encode(newAllowedAMMs));
    }

    function rebalanceByCreditMultipliers() public view returns(uint256[] memory) {
        return _rebalanceByCreditMultipliers;
    }

    function differences()
        public
        view
        returns (uint256 credit, uint256 debt)
    {
        uint256 totalSupply = INativeV1(_collection).totalSupply(_objectId);
        uint256 effectiveAmount = 0;
        for(uint256 i = 0; i < _allowedAMMs.length; i++) {
            for(uint256 j = 0; j < _allowedAMMs[i].liquidityProviders.length; j++) {
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
        uint256 remainingDecimals = _decimals - tokenDecimals;
        uint256 result = amount == 0 ? token.balanceOf(address(this)) : amount;
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
            require(id == _objectId, "Only uSD id allowed here");
            (uint256 action, bytes memory payload) = abi.decode(data, (uint256, bytes));
            if(action == 1) {
                _rebalanceByDebt(from, value);
            } else {
                _burn(from, value, payload);
            }
            return this.onERC1155Received.selector;
    }

    function _burn(address from, uint256 value, bytes memory payload) private {
        (uint256 ammPosition, uint256 liquidityProviderPosition, uint256 liquidityProviderAmount) = abi.decode(payload, (uint256, uint256, uint256));
        uint256 toBurn = _normalizeAndSumAmounts(ammPosition, liquidityProviderPosition, liquidityProviderAmount);
        require(value >= toBurn, "Insufficient Amount");
        if(value > toBurn) {
            INativeV1(_collection).safeTransferFrom(address(this), from, _objectId, value - toBurn, "");
        }
        INativeV1(_collection).burn(_objectId, toBurn);
        _removeLiquidity(from, ammPosition, liquidityProviderPosition, liquidityProviderAmount);
    }

    function _rebalanceByDebt(address from, uint256 value) private {
        (, uint256 debt) = differences();
        require(value <= debt, "Cannot Burn this amount");
        INativeV1(_collection).burn(_objectId, value);
        
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
        require(msg.sender != _collection, "Cannot send uSD to this call");
        address[] memory tokens = new address[](ids.length);
        uint256[] memory newValues = new uint256[](ids.length);
        for(uint256 i = 0; i < ids.length; i++) {
            IERC20WrapperV1 wrapper = IERC20WrapperV1(msg.sender);
            wrapper.burn(ids[i], values[i]);
            IERC20 token = IERC20(tokens[i] = wrapper.source(ids[i]));
            newValues[i] = token.balanceOf(address(this));
        }
        (uint256 ammPosition, uint256 liquidityProviderPosition, uint256 liquidityProviderAmount) = abi.decode(data, (uint256, uint256, uint256));
        _addLiquidity(tokens, newValues, from, ammPosition, liquidityProviderPosition, liquidityProviderAmount);
        USDExtension(_extension).mint(_normalizeAndSumAmounts(ammPosition, liquidityProviderPosition, liquidityProviderAmount), from);
        return this.onERC1155BatchReceived.selector;
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
        USDExtension(_extension).mint(credit, address(this));
        uint256 forDFO = (credit * _rebalanceByCreditMultipliers[0]) / _rebalanceByCreditMultipliers[1];
        IERC20(_interoperableInterfaceAddress).transfer(IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDWalletAddress(), forDFO);
        for(uint256 i = 0; i < _creditReceivers.length; i++) {
            uint256 numerator = _rebalanceByCreditMultipliers[2 + (2 * i)];
            uint256 denominator = _rebalanceByCreditMultipliers[3 + (2 * i)];
            uint256 value = (credit * numerator) / denominator;
            INativeV1(_collection).safeTransferFrom(address(this), _creditReceivers[i], _objectId, value, "");
        }
    }

    modifier _forAllowedAMMAndLiquidityProvider(uint256 ammIndex, uint256 liquidityProviderIndex) {
        require(
            ammIndex >= 0 && ammIndex < _allowedAMMs.length,
            "Unknown AMM!"
        );
        require(
            liquidityProviderIndex >= 0 && liquidityProviderIndex < _allowedAMMs[ammIndex].liquidityProviders.length,
            "Unknown Liquidity Provider!"
        );
        _;
    }

    function _addLiquidity(
        address[] memory tokens,
        uint256[] memory amounts,
        address owner,
        uint256 ammPosition,
        uint256 liquidityProviderPosition,
        uint256 liquidityProviderAmount
    )
        private
        _forAllowedAMMAndLiquidityProvider(ammPosition, liquidityProviderPosition)
    {
        LiquidityProviderData memory data = LiquidityProviderData(
            _allowedAMMs[ammPosition].liquidityProviders[liquidityProviderPosition],
            liquidityProviderAmount,
            tokens,
            amounts,
            owner,
            address(this)
        );
        bool ethInvolved = false;
        uint256 ethValue = 0;
        for(uint256 i = 0 ; i < tokens.length; i++) {
            if(tokens[i] == address(0)) {
                ethInvolved = true;
                ethValue += amounts[i];
            }
        }
        _checkAllowance(tokens, amounts, _allowedAMMs[ammPosition].ammAddress);
        if(ethInvolved) {
            IAMM(_allowedAMMs[ammPosition].ammAddress).addLiquidity{value : ethValue}(data);
            return;
        }
        IAMM(_allowedAMMs[ammPosition].ammAddress).addLiquidity(data);
    }

    function _removeLiquidity(
        address owner,
        uint256 ammPosition,
        uint256 liquidityProviderPosition,
        uint256 liquidityProviderAmount
    )
        private
        _forAllowedAMMAndLiquidityProvider(ammPosition, liquidityProviderPosition)
    {
        IAMM amm = IAMM(_allowedAMMs[ammPosition].ammAddress);
        LiquidityProviderData memory data = LiquidityProviderData(
            _allowedAMMs[ammPosition].liquidityProviders[liquidityProviderPosition],
            liquidityProviderAmount,
            amm.tokens(_allowedAMMs[ammPosition].liquidityProviders[liquidityProviderPosition]),
            new uint256[](0),
            owner,
            address(this)
        );
        _checkAllowance(_allowedAMMs[ammPosition].liquidityProviders[liquidityProviderPosition], liquidityProviderAmount, _allowedAMMs[ammPosition].ammAddress);
        amm.removeLiquidity(data);
    }

    function _normalizeAmounts(uint256 ammPosition, uint256 liquidityProviderPosition, uint256 liquidityProviderAmount)
        private
        view
        returns (uint256[] memory amounts)
    {
        IERC20 liquidityProvider = IERC20(_allowedAMMs[ammPosition].liquidityProviders[liquidityProviderPosition]);
        amounts = IAMM(_allowedAMMs[ammPosition].ammAddress).byAmount(address(liquidityProvider), liquidityProviderAmount != 0 ? liquidityProviderAmount : liquidityProvider.balanceOf(address(this)), _decimals);
    }

    function _normalizeAndSumAmounts(uint256 ammPosition, uint256 liquidityProviderPosition, uint256 liquidityProviderAmount)
        private
        view
        returns(uint256 amount) {
            uint256[] memory amounts = _normalizeAmounts(ammPosition, liquidityProviderPosition, liquidityProviderAmount);
            for(uint256 i = 0; i < amounts.length; i++) {
                amount += amounts[i];
            }
        }

    function _transferToMeAndCheckAllowance(address[] memory tokens, uint256[] memory amounts, address operator) internal virtual {
        for(uint256 i = 0; i < tokens.length; i++) {
            _transferToMeAndCheckAllowance(tokens[i], amounts[i], operator);
        }
    }

    function _transferToMeAndCheckAllowance(address tokenAddress, uint256 value, address operator) internal virtual {
        _transferToMe(tokenAddress, value);
        _checkAllowance(tokenAddress, value, operator);
    }

    function _transferToMe(address tokenAddress, uint256 value) internal virtual {
        if(tokenAddress == address(0)) {
            return;
        }
        _safeTransferFrom(tokenAddress, msg.sender, address(this), value);
    }

    function _checkAllowance(address[] memory tokens, uint256[] memory amounts, address operator) internal virtual {
        for(uint256 i = 0; i < tokens.length; i++) {
            _checkAllowance(tokens[i], amounts[i], operator);
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