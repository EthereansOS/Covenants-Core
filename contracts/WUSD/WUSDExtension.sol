//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma abicoder v2;

import "./util/IEthItemOrchestrator.sol";
import "./util/INativeV1.sol";
import "./util/IERC20.sol";
import "../amm-aggregator/common/IAMM.sol";
import "./AllowedAMM.sol";
import "./IWUSDExtension.sol";

contract WUSDExtension is IWUSDExtension {

    uint256 private constant DECIMALS = 18;

    address private _controller;

    address private _collection;

    uint256 private _mainItemObjectId;
    address private _mainItemInteroperableAddress;

    constructor(address orchestrator) {
        _controller = msg.sender;
        (_collection,) = IEthItemOrchestrator(orchestrator).createNative(abi.encodeWithSignature("init(string,string,bool,string,address,bytes)", "Covenants Wrapped USD", "WUSD", true, "ipfs://ipfs/QmbFb9QdwSV1i8F1FhvBoL7XuCU7D1wRTLRRi23Zvu8Z9J", address(this), ""), "");
        (_mainItemObjectId, _mainItemInteroperableAddress) = _mintEmpty("Wrapped USD", "WUSD", "ipfs://ipfs/QmTj9k7vq8DqLFuS3TrGGNDaacHL2cTgLjJ6Tu8ZbKwTHm", true);
    }

    function collection() public view returns (address) {
        return _collection;
    }

    function data() public view returns (address, uint256, address) {
        return (_collection, _mainItemObjectId, _mainItemInteroperableAddress);
    }

    function controller() public override view returns (address) {
        return _controller;
    }

    modifier controllerOnly() {
        require(msg.sender == _controller, "Unauthorized action");
        _;
    }

    function mintEmpty(string memory tokenName, string memory tokenSymbol, string memory objectUri, bool editable) public controllerOnly returns(uint256 objectId, address interoperableInterfaceAddress) {
        return _mintEmpty(tokenName, tokenSymbol, objectUri, editable);
    }

    function _mintEmpty(string memory tokenName, string memory tokenSymbol, string memory objectUri, bool editable) private returns(uint256 objectId, address interoperableInterfaceAddress) {
        INativeV1 theCollection = INativeV1(_collection);
        (objectId, interoperableInterfaceAddress) = theCollection.mint(10**18, tokenName, tokenSymbol, objectUri, editable);
        theCollection.burn(objectId, theCollection.balanceOf(address(this), objectId));
    }

    function setCollectionUri(string memory uri) public controllerOnly {
        INativeV1(_collection).setUri(uri);
    }

    function setItemUri(uint256 existingObjectId, string memory uri) public controllerOnly {
        INativeV1(_collection).setUri(existingObjectId, uri);
    }

    function makeReadOnly(uint256 objectId) public controllerOnly {
        INativeV1(_collection).makeReadOnly(objectId);
    }

    function mintFor(address ammPlugin, address liquidityPoolAddress, uint256 liquidityPoolAmount, address receiver) public controllerOnly {
        _safeTransferFrom(liquidityPoolAddress, msg.sender, address(this), liquidityPoolAmount);
        _mint(_mainItemObjectId, _normalizeAndSumAmounts(ammPlugin, liquidityPoolAddress, liquidityPoolAmount), receiver);
    }

    function mintForRebalanceByCredit(AllowedAMM[] memory amms) public controllerOnly returns(uint256 credit) {
        uint256 totalSupply = INativeV1(_collection).totalSupply(_mainItemObjectId);
        for(uint256 i = 0; i < amms.length; i++) {
            for(uint256 j = 0; j < amms[i].liquidityPools.length; j++) {
                credit += _normalizeAndSumAmounts(amms[i].ammAddress, amms[i].liquidityPools[j], IERC20(amms[i].liquidityPools[j]).balanceOf(address(this)));
            }
        }
        require(credit > totalSupply, "No credit");
        _mint(_mainItemObjectId, credit = (credit - totalSupply), msg.sender);
    }

    function burnFor(uint256 objectId, uint256 value, address receiver) public controllerOnly {
        _safeTransferFrom(_mainItemInteroperableAddress, msg.sender, address(this), INativeV1(_collection).toInteroperableInterfaceAmount(_mainItemObjectId, value));
        INativeV1(_collection).burn(_mainItemObjectId, value);
        _mint(objectId, value, receiver);
    }

    function _mint(uint256 objectId, uint256 amount, address receiver) private {
        INativeV1(_collection).mint(objectId, amount);
        INativeV1(_collection).safeTransferFrom(address(this), receiver, objectId, INativeV1(_collection).balanceOf(address(this), objectId), "");
    }

    function burnFor(address from, uint256 value, address ammPlugin, address liquidityPoolAddress, uint256 liquidityPoolAmount, address liquidityPoolReceiver) public controllerOnly {
        _safeTransferFrom(_mainItemInteroperableAddress, msg.sender, address(this), INativeV1(_collection).toInteroperableInterfaceAmount(_mainItemObjectId, value));
        uint256 toBurn = _normalizeAndSumAmounts(ammPlugin, liquidityPoolAddress, liquidityPoolAmount);
        require(value >= toBurn, "Insufficient Amount");
        if(value > toBurn) {
            INativeV1(_collection).safeTransferFrom(address(this), from, _mainItemObjectId, value - toBurn, "");
        }
        INativeV1(_collection).burn(_mainItemObjectId, toBurn);
        _safeTransfer(liquidityPoolAddress, liquidityPoolReceiver, liquidityPoolAmount);
    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) internal {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFER_FAILED');
    }

    function _safeTransferFrom(address erc20TokenAddress, address from, address to, uint256 value) private {
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

    function _normalizeAndSumAmounts(address ammPlugin, address liquidityPoolAddress, uint256 liquidityPoolAmount)
        private
        view
        returns(uint256 amount) {
            IERC20 liquidityPool = IERC20(liquidityPoolAddress);
            (uint256[] memory amounts, address[] memory tokens) = IAMM(ammPlugin).byLiquidityPoolAmount(address(liquidityPool), liquidityPoolAmount);
            for(uint256 i = 0; i < amounts.length; i++) {
                amount += _normalizeTokenAmountToDefaultDecimals(tokens[i], amounts[i]);
            }
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