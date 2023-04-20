//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/IRoutinesExtension.sol";
import "@ethereansos/swissknife/contracts/generic/impl/LazyInitCapableElement.sol";
import { IERC20Full } from "@ethereansos/swissknife/contracts/lib/GeneralUtilities.sol";

contract RoutinesExtension is IRoutinesExtension, LazyInitCapableElement {

    bool public override active;

    constructor(bytes memory lazyInitData) LazyInitCapableElement(lazyInitData) {}

    receive() external payable {
    }

    function _lazyInit(bytes memory lazyInitData) internal override returns(bytes memory) {
        require(host != address(0), "host");
        return "";
    }

    function _supportsInterface(bytes4 selector) internal override view returns(bool) {

    }

    function setActive(bool _active) external override virtual authorizedOnly {
        active = _active;
    }

    function receiveTokens(address[] memory tokenAddresses, uint256[] memory transferAmounts, uint256[] memory amountsToMint) external override initializerOnly {
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            if(transferAmounts[i] > 0) {
                if(tokenAddresses[i] == address(0)) {
                    (bool result,) = msg.sender.call{value:transferAmounts[i]}("");
                    require(result, "ETH transfer failed");
                    continue;
                }
                _safeTransfer(tokenAddresses[i], msg.sender, transferAmounts[i]);
            }
            if(amountsToMint[i] > 0) {
                _mintAndTransfer(tokenAddresses[i], msg.sender, amountsToMint[i]);
            }
        }
    }

    function setEntry(RoutinesEntry memory newEntry, RoutinesOperation[] memory newOperations) external override authorizedOnly {
        IRoutines(initializer).setEntry(newEntry, newOperations);
    }

    function flushBack(address[] memory tokenAddresses) external override authorizedOnly {
        IRoutines(initializer).flushBack(tokenAddresses);
    }

    function deactivationByFailure() external override initializerOnly {
        active = false;
    }

    function burnToken(address erc20TokenAddress, uint256 value) external override initializerOnly {
        _safeTransferFrom(erc20TokenAddress, initializer, address(this), value);
        _burn(erc20TokenAddress, value);
    }

    /** INTERNAL METHODS */

    function _mintAndTransfer(address erc20TokenAddress, address recipient, uint256 value) internal virtual {
        IERC20Full(erc20TokenAddress).mint(recipient, value);
    }

    function _burn(address erc20TokenAddress, uint256 value) internal virtual {
        IERC20Full(erc20TokenAddress).burn(value);
    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) internal virtual {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20Full(erc20TokenAddress).transfer.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFER_FAILED');
    }

    function _safeTransferFrom(address erc20TokenAddress, address from, address to, uint256 value) internal {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20Full(erc20TokenAddress).transferFrom.selector, from, to, value));
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