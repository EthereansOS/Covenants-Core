//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/IFarmingExtension.sol";
import "@ethereansos/swissknife/contracts/generic/impl/LazyInitCapableElement.sol";
import { IERC20Full, TransferUtilities } from "@ethereansos/swissknife/contracts/lib/GeneralUtilities.sol";

contract FarmingExtension is IFarmingExtension, LazyInitCapableElement {
    using TransferUtilities for address;

    address internal _rewardTokenAddress;
    bool internal _byMint;
    address internal _treasury;

    constructor(bytes memory lazyInitData) LazyInitCapableElement(lazyInitData) {}

    function _lazyInit(bytes memory lazyInitData) internal override returns(bytes memory lazyInitResponse) {
        address _host = host;
        require(_host != address(0), "host");
        _rewardTokenAddress = IFarming(initializer).rewardTokenAddress();
        address treasury;
        (_byMint, treasury) = abi.decode(lazyInitData, (bool, address));
        _treasury = treasury != address(0) ? treasury : _host;
        return "";
    }

    function _supportsInterface(bytes4 selector) internal override view returns(bool) {
    }

    receive() external payable {
        require(initializer != address(0) && _rewardTokenAddress == address(0), "ETH not allowed");
    }

    function data() external view override returns(address farmMainContract, address _host, address rewardTokenAddress, bool byMint, address treasury) {
        return (initializer, host, _rewardTokenAddress, _byMint, _treasury);
    }

    function setTreasury(address treasury) external override authorizedOnly {
        _treasury = treasury;
    }

    function setFarmingSetups(FarmingSetupConfiguration[] memory farmingSetups) external virtual override authorizedOnly {
        IFarming(initializer).setFarmingSetups(farmingSetups);
    }

    function transferTo(uint256 amount) external virtual override initializerOnly {
        return _byMint ? _mintAndTransfer(_rewardTokenAddress, initializer, amount) : _rewardTokenAddress.safeTransfer(initializer, amount);
    }

    function backToYou(uint256 amount) payable external virtual override initializerOnly {
        if(_rewardTokenAddress != address(0)) {
            _rewardTokenAddress.safeTransferFrom(msg.sender, _byMint ? address(this) : _treasury, amount);
            if(_byMint) {
                _burn(_rewardTokenAddress, amount);
            }
        } else {
            require(msg.value == amount, "invalid sent amount");
            address treasury = _treasury;
            if(treasury != address(this)) {
                address(0).safeTransfer(treasury, amount);
            }
        }
    }

    function _mintAndTransfer(address erc20TokenAddress, address recipient, uint256 value) internal virtual {
        IERC20Full(erc20TokenAddress).mint(recipient, value);
    }

    function _burn(address erc20TokenAddress, uint256 value) internal virtual {
        erc20TokenAddress.safeBurn(value);
    }
}