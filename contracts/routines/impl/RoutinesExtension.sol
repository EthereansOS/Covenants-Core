//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/IRoutinesExtension.sol";
import "@ethereansos/swissknife/contracts/generic/impl/LazyInitCapableElement.sol";
import { IERC20Full as IERC20, TransferUtilities } from "@ethereansos/swissknife/contracts/lib/GeneralUtilities.sol";

contract RoutinesExtension is IRoutinesExtension, LazyInitCapableElement {
    using TransferUtilities for address;

    bool public override active;

    constructor(bytes memory lazyInitData) LazyInitCapableElement(lazyInitData) {}

    receive() external payable {}

    function _lazyInit(bytes memory lazyInitData) internal override returns(bytes memory) {
        require(host != address(0), "host");
        return "";
    }

    function _supportsInterface(bytes4 selector) internal override view returns(bool) {

    }

    function setActive(bool _active) external override virtual authorizedOnly {
        active = _active;
    }

    function setEntry(RoutinesEntry memory newEntry, RoutinesOperation[] memory newOperations) external override authorizedOnly {
        IRoutines(initializer).setEntry(newEntry, newOperations);
    }

    function flushBack(address[] memory tokenAddresses) external override authorizedOnly {
        IRoutines(initializer).flushBack(tokenAddresses);
    }

    function sendAndMintTokens(address[] memory tokenAddresses, uint256[] memory amountsToTransfer, uint256[] memory amountsToMint) external override initializerOnly returns(uint256[] memory transferredAmounts, uint256[] memory mintedAmounts) {
        transferredAmounts = new uint256[](amountsToTransfer.length);
        mintedAmounts = new uint256[](amountsToMint.length);
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            if(amountsToTransfer[i] > 0) {
                transferredAmounts[i] = tokenAddresses[i].safeTransfer(msg.sender, amountsToTransfer[i]);
            }
            if(amountsToMint[i] > 0) {
                mintedAmounts[i] = _mintAndTransfer(tokenAddresses[i], msg.sender, amountsToMint[i]);
            }
        }
    }

    function deactivationByFailure() external override initializerOnly {
        active = false;
    }

    function burn(address erc20TokenAddress, uint256 value) external override initializerOnly {
        value = erc20TokenAddress.safeTransferFrom(initializer, address(this), value);
        _burn(erc20TokenAddress, value);
    }

    function _mintAndTransfer(address erc20TokenAddress, address recipient, uint256 value) internal virtual returns(uint256 minted) {
        IERC20(erc20TokenAddress).mint(recipient, minted = value);
    }

    function _burn(address erc20TokenAddress, uint256 value) internal virtual {
        erc20TokenAddress.safeBurn(value);
    }
}