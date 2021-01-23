//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma abicoder v2;

import "./WUSDExtension.sol";
import "./util/DFOHub.sol";
import "./util/ERC1155Receiver.sol";
import "./util/INativeV1.sol";
import "./util/IERC20WrapperV1.sol";
import "./util/IERC20.sol";
import "./AllowedAMM.sol";
import "./IWUSDNoteController.sol";
import "../amm-aggregator/common/IAMM.sol";
import "../amm-aggregator/common/AMMData.sol";

contract WUSDExtensionController is ERC1155Receiver {

    uint256 public constant ONE_HUNDRED = 10000;

    uint256 private constant DECIMALS = 18;

    address private _doubleProxy;

    uint256 public rebalanceByCreditBlockInterval;

    address private _extension;

    address private _collection;

    uint256 private _wusdObjectId;
    address private _wusdInteroperableInterfaceAddress;

    uint256 private _wusdNote2ObjectId;
    address private _wusdNote2InteroperableInterfaceAddress;
    address private _wusdNote2Controller;
    uint256 private _wusdNote2Percentage;

    uint256 private _wusdNote5ObjectId;
    address private _wusdNote5InteroperableInterfaceAddress;
    address private _wusdNote5Controller;
    uint256 private _wusdNote5Percentage;

    uint256 private _lastRedeemBlock;

    AllowedAMM[] private _allowedAMMs;

    uint256[] private _rebalanceByCreditPercentages;

    address[] private _rebalanceByCreditReceivers;

    uint256 private _rebalanceByCreditPercentageForCaller;

    struct WUSDInitializer {
        address doubleProxyAddress;
        address[] rebalanceByCreditReceivers;
        uint256[] rebalanceByCreditPercentages;
        uint256 rebalanceByCreditPercentageForCaller;
        uint256 rebalanceByCreditBlockInterval;
        bytes allowedAMMsBytes;
        address wusdExtension;
        uint256 wusdObjectId;
        uint256 wusdNote2ObjectId;
        address wusdNote2Controller;
        uint256 wusdNote2Percentage;
        uint256 wusdNote5ObjectId;
        address wusdNote5Controller;
        uint256 wusdNote5Percentage;
        address orchestratorAddress;
        string[] names;
        string[] symbols;
        string[] uris;
    }

    constructor(bytes memory wusdInitializerBytes) {
        WUSDInitializer memory wusdInitializer = abi.decode(wusdInitializerBytes, (WUSDInitializer));
        _doubleProxy = wusdInitializer.doubleProxyAddress;
        rebalanceByCreditBlockInterval = wusdInitializer.rebalanceByCreditBlockInterval;
        WUSDExtension wusdExtension = WUSDExtension(_extension = wusdInitializer.wusdExtension != address(0) ? wusdInitializer.wusdExtension : address(new WUSDExtension(wusdInitializer.orchestratorAddress, wusdInitializer.names[0], wusdInitializer.symbols[0], wusdInitializer.uris[0])));
        INativeV1 wusdCollection = INativeV1(_collection = wusdExtension.collection());
        if(wusdInitializer.wusdObjectId == 0) {
            (_wusdObjectId, _wusdInteroperableInterfaceAddress) = wusdExtension.mintEmpty(wusdInitializer.names[1], wusdInitializer.symbols[1], wusdInitializer.uris[1], true);
        } else {
            _wusdInteroperableInterfaceAddress = address(wusdCollection.asInteroperable(_wusdObjectId = wusdInitializer.wusdObjectId));
            _wusdNote2InteroperableInterfaceAddress = address(wusdCollection.asInteroperable(_wusdNote2ObjectId = wusdInitializer.wusdNote2ObjectId));
            _wusdNote5InteroperableInterfaceAddress = address(wusdCollection.asInteroperable(_wusdNote5ObjectId = wusdInitializer.wusdNote5ObjectId));
            _checkNoteController(_wusdNote2Controller = wusdInitializer.wusdNote2Controller, _wusdNote2ObjectId, 2);
            _checkNoteController(_wusdNote5Controller = wusdInitializer.wusdNote5Controller, _wusdNote5ObjectId, 5);
        }
        _wusdNote2Percentage = wusdInitializer.wusdNote2Percentage;
        _wusdNote5Percentage = wusdInitializer.wusdNote5Percentage;
        _setRebalanceByCreditData(wusdInitializer.rebalanceByCreditReceivers, wusdInitializer.rebalanceByCreditPercentages, wusdInitializer.rebalanceByCreditPercentageForCaller);
        _setAllowedAMMs(wusdInitializer.allowedAMMsBytes);
    }

    function initNotes(address[] memory controllers, string[] memory names, string[] memory symbols, string[] memory uris) public {
        require(_wusdNote2InteroperableInterfaceAddress == address(0), "already init");
        WUSDExtension wusdExtension = WUSDExtension(_extension);
        (_wusdNote2ObjectId, _wusdNote2InteroperableInterfaceAddress) = wusdExtension.mintEmpty(names[0], symbols[0], uris[0], true);
        (_wusdNote5ObjectId, _wusdNote5InteroperableInterfaceAddress) = wusdExtension.mintEmpty(names[1], symbols[1], uris[1], true);
        IWUSDNoteController(_wusdNote2Controller = controllers[0]).init(_collection, _wusdObjectId, _wusdNote2ObjectId, 2);
        IWUSDNoteController(_wusdNote5Controller = controllers[1]).init(_collection, _wusdObjectId, _wusdNote5ObjectId, 5);
    }

    receive() external payable {
    }

    function _checkNoteController(address noteController, uint256 wusdNoteObjectIdInput, uint256 multiplierInput) private {
        (address collectionAddress, uint256 wusdObjectId, uint256 wusdNoteObjectId, uint256 multiplier) = IWUSDNoteController(noteController).info();
        if(collectionAddress == address(0)) {
            IWUSDNoteController(noteController).init(_collection, _wusdObjectId, wusdNoteObjectIdInput, multiplierInput);
            (collectionAddress, wusdObjectId, wusdNoteObjectId, multiplier) = IWUSDNoteController(noteController).info();
        }
        require(collectionAddress == _collection, "Wrong collection");
        require(wusdObjectId == _wusdObjectId, "Wrong WUSD Object Id");
        require(wusdNoteObjectId == wusdNoteObjectIdInput, "Wrong WUSD Note Object Id");
        require(multiplier == multiplierInput, "Wrong WUSD Note multiplier");
    }

    function _setRebalanceByCreditData(address[] memory rebalanceByCreditReceivers, uint256[] memory rebalanceByCreditPercentages, uint256 rebalanceByCreditPercentageForCaller) private {
        require((_rebalanceByCreditPercentages = rebalanceByCreditPercentages).length == (_rebalanceByCreditReceivers = rebalanceByCreditReceivers).length, "Invalid lengths");
        uint256 percentage = _rebalanceByCreditPercentageForCaller = rebalanceByCreditPercentageForCaller + _wusdNote2Percentage + _wusdNote5Percentage;
        for(uint256 i = 0; i < rebalanceByCreditReceivers.length; i++) {
            require(rebalanceByCreditReceivers[i] != address(0), "Void address");
            require(rebalanceByCreditPercentages[i] > 0, "Zero percentage");
            percentage += rebalanceByCreditPercentages[i];
        }
        require(percentage <= ONE_HUNDRED, "More than one hundred");
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

    function wusdInfo() public view returns (address, uint256, address) {
        return (_collection, _wusdObjectId, _wusdInteroperableInterfaceAddress);
    }

    function wusdNote2Info() public view returns (address, uint256, address, address, uint256) {
        return (_collection, _wusdNote2ObjectId, _wusdNote2InteroperableInterfaceAddress, _wusdNote2Controller, _wusdNote2Percentage);
    }

    function wusdNote5Info() public view returns (address, uint256, address, address, uint256) {
        return (_collection, _wusdNote5ObjectId, _wusdNote5InteroperableInterfaceAddress, _wusdNote5Controller, _wusdNote5Percentage);
    }

    function rebalanceByCreditReceiversInfo() public view returns (address[] memory, uint256[] memory, uint256, address) {
        return (_rebalanceByCreditReceivers, _rebalanceByCreditPercentages, _rebalanceByCreditPercentageForCaller, IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDWalletAddress());
    }

    modifier byDFO virtual {
        require(_isFromDFO(msg.sender), "Unauthorized action");
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
        WUSDExtension(_extension).setController(controller);
    }

    function setCollectionUri(string memory uri) public byDFO {
        WUSDExtension(_extension).setCollectionUri(uri);
    }

    function setItemUri(uint256 existingObjectId, string memory uri) public byDFO {
        WUSDExtension(_extension).setItemUri(existingObjectId, uri);
    }

    function setController(address newController) public byDFO {
        WUSDExtension(_extension).setController(newController);
    }

    function setrebalanceByCreditBlockInterval(uint256 newrebalanceByCreditBlockInterval) public byDFO {
        rebalanceByCreditBlockInterval = newrebalanceByCreditBlockInterval;
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
        uint256 totalSupply = INativeV1(_collection).totalSupply(_wusdObjectId);
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
            require(msg.sender == _collection, "Only WUSD collection allowed here");
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

        require(msg.sender == _collection, "Only WUSD collection allowed here");
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
            require(id == _wusdObjectId, "Only WUSD id allowed here");
            if(from == _extension) {
                return;
            }
            (uint256 action, bytes memory payload) = abi.decode(data, (uint256, bytes));
            if(action == 1) {
                _rebalanceByDebt(from, value, payload);
            } else {
                _burn(from, value, payload);
            }
    }

    function _burn(address from, uint256 value, bytes memory payload) private {
        (uint256 ammPosition, uint256 liquidityPoolPosition, uint256 liquidityPoolAmount, bool keepLiquidityPool) = abi.decode(payload, (uint256, uint256, uint256, bool));
        uint256 toBurn = _normalizeAndSumAmounts(ammPosition, liquidityPoolPosition, liquidityPoolAmount);
        require(value >= toBurn, "Insufficient Amount");
        if(value > toBurn) {
            INativeV1(_collection).safeTransferFrom(address(this), from, _wusdObjectId, value - toBurn, "");
        }
        INativeV1(_collection).burn(_wusdObjectId, toBurn);
        _removeLiquidity(from, ammPosition, liquidityPoolPosition, liquidityPoolAmount, keepLiquidityPool);
    }

    function _rebalanceByDebt(address from, uint256 value, bytes memory payload) private {
        (, uint256 debt) = differences();
        require(value <= debt, "Cannot Burn this amount");
        INativeV1(_collection).burn(_wusdObjectId, value);
        uint256 note = abi.decode(payload, (uint256));
        WUSDExtension(_extension).mint(note == 2 ? _wusdNote2ObjectId : _wusdNote5ObjectId, value, from);
    }

    function rebalanceByCredit() public {
        require(block.number >= (_lastRedeemBlock + rebalanceByCreditBlockInterval), "Unauthorized action");
        _lastRedeemBlock = block.number;
        (uint256 credit, ) = differences();
        WUSDExtension(_extension).mint(_wusdObjectId, credit, address(this));
        uint256 availableCredit = credit;
        uint256 reward = 0;
        if(_rebalanceByCreditPercentageForCaller > 0) {
            IERC20(_wusdInteroperableInterfaceAddress).transfer(msg.sender, reward = _calculatePercentage(credit, _rebalanceByCreditPercentageForCaller));
            availableCredit -= reward;
        }
        if(_wusdNote2Percentage > 0) {
            IERC20(_wusdInteroperableInterfaceAddress).transfer(_wusdNote2Controller, reward = _calculatePercentage(credit, _wusdNote2Percentage));
            availableCredit -= reward;
        }
        if(_wusdNote5Percentage > 0) {
            IERC20(_wusdInteroperableInterfaceAddress).transfer(_wusdNote5Controller, reward = _calculatePercentage(credit, _wusdNote5Percentage));
            availableCredit -= reward;
        }
        for(uint256 i = 0; i < _rebalanceByCreditReceivers.length; i++) {
            IERC20(_wusdInteroperableInterfaceAddress).transfer(_rebalanceByCreditReceivers[i], reward = _calculatePercentage(credit, _rebalanceByCreditPercentages[i]));
            availableCredit -= reward;
        }
        if(availableCredit > 0) {
            IERC20(_wusdInteroperableInterfaceAddress).transfer(IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDWalletAddress(), availableCredit);
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
        uint256 liquidityPoolAmount,
        bool byLiquidityPool
    )
        public
        _forAllowedAMMAndLiquidityPool(ammPosition, liquidityPoolPosition)
        returns(uint256 toMint)
    {
        address liquidityPoolAddress = _allowedAMMs[ammPosition].liquidityPools[liquidityPoolPosition];
        uint256[] memory spent;
        uint256[] memory amounts;
        address[] memory tokens;
        if(byLiquidityPool) {
            _safeTransferFrom(liquidityPoolAddress, msg.sender, _extension, toMint = liquidityPoolAmount);
        } else {
            IAMM amm = IAMM(_allowedAMMs[ammPosition].ammAddress);
            (amounts, tokens) = amm.byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount);
            for(uint256 i = 0; i < tokens.length; i++) {
                _safeTransferFrom(tokens[i], msg.sender, address(this), amounts[i]);
                _safeApprove(tokens[i], address(amm), amounts[i]);
            }
            (toMint, spent,) = IAMM(_allowedAMMs[ammPosition].ammAddress).addLiquidity(LiquidityPoolData(
                liquidityPoolAddress,
                liquidityPoolAmount,
                address(0),
                true,
                false,
                _extension
            ));
        }

        WUSDExtension(_extension).mint(_wusdObjectId, _normalizeAndSumAmounts(ammPosition, liquidityPoolPosition, toMint), msg.sender);

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
        uint256 liquidityPoolAmount,
        bool keepLiquidityPool
    )
        private
        _forAllowedAMMAndLiquidityPool(ammPosition, liquidityPoolPosition)
    {
        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = _allowedAMMs[ammPosition].liquidityPools[liquidityPoolPosition];
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = liquidityPoolAmount;
        address[] memory receivers = new address[](1);
        receivers[0] = keepLiquidityPool ? owner : address(this);
        WUSDExtension(_extension).send(tokenAddresses, amounts, receivers);
        if(!keepLiquidityPool) {
            IAMM amm = IAMM(_allowedAMMs[ammPosition].ammAddress);
            _checkAllowance(_allowedAMMs[ammPosition].liquidityPools[liquidityPoolPosition], liquidityPoolAmount, address(amm));
            amm.removeLiquidity(LiquidityPoolData(
                _allowedAMMs[ammPosition].liquidityPools[liquidityPoolPosition],
                liquidityPoolAmount,
                address(0),
                true,
                false,
                owner
            ));
        }
    }

    function _normalizeAndSumAmounts(uint256 ammPosition, uint256 liquidityPoolPosition, uint256 liquidityPoolAmount)
        private
        view
        returns(uint256 amount) {
            IERC20 liquidityPool = IERC20(_allowedAMMs[ammPosition].liquidityPools[liquidityPoolPosition]);
            (uint256[] memory amounts, address[] memory tokens) = IAMM(_allowedAMMs[ammPosition].ammAddress).byLiquidityPoolAmount(address(liquidityPool), liquidityPoolAmount != 0 ? liquidityPoolAmount : liquidityPool.balanceOf(_extension));
            for(uint256 i = 0; i < amounts.length; i++) {
                amount += _normalizeTokenAmountToDefaultDecimals(tokens[i], amounts[i]);
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

    function _normalizeTokenAmountToDefaultDecimals(address tokenAddress, uint256 amount) internal virtual view returns(uint256) {
        uint256 remainingDecimals = DECIMALS;
        IERC20 token = IERC20(tokenAddress);
        remainingDecimals -= token.decimals();

        if(remainingDecimals == 0) {
            return amount;
        }

        return amount * (remainingDecimals == 0 ? 1 : (10**remainingDecimals));
    }
}