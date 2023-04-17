//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/IRoutinesExtension.sol";
import "../../util/IERC20.sol";
import "../../util/IERC20Mintable.sol";
import "../../util/IERC20Burnable.sol";

contract RoutinesExtension is IRoutinesExtension {

    address private _host;

    address private _RoutinesContract;

    bool public override active;

    modifier RoutinesOnly() {
        require(_RoutinesContract == msg.sender, "Unauthorized");
        _;
    }

    modifier hostOnly() {
        require(_host == msg.sender, "Unauthorized");
        _;
    }

    receive() external payable {
    }

    function init(address host) override public virtual {
        require(_host == address(0), "Already init");
        require((_host = host) != address(0), "blank host");
        _RoutinesContract = msg.sender;
    }

    function setHost(address host) public virtual override hostOnly {
        _host = host;
    }

    function data() view public override returns(address RoutinesContract, address host) {
        return(_RoutinesContract, _host);
    }

    function setActive(bool _active) public override virtual hostOnly {
        active = _active;
    }

    function receiveTokens(address[] memory tokenAddresses, uint256[] memory transferAmounts, uint256[] memory amountsToMint) public override RoutinesOnly {
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

    function setEntry(RoutinesEntry memory newEntry, RoutinesOperation[] memory newOperations) public override hostOnly {
        IRoutines(_RoutinesContract).setEntry(newEntry, newOperations);
    }

    function flushBack(address[] memory tokenAddresses) public override hostOnly {
        IRoutines(_RoutinesContract).flushBack(tokenAddresses);
    }

    function deactivationByFailure() public override RoutinesOnly {
        active = false;
    }

    function burnToken(address erc20TokenAddress, uint256 value) external override RoutinesOnly {
        _safeTransferFrom(erc20TokenAddress, _RoutinesContract, address(this), value);
        _burn(erc20TokenAddress, value);
    }

    /** INTERNAL METHODS */

    function _mintAndTransfer(address erc20TokenAddress, address recipient, uint256 value) internal virtual {
        IERC20Mintable(erc20TokenAddress).mint(recipient, value);
    }

    function _burn(address erc20TokenAddress, uint256 value) internal virtual {
        IERC20Burnable(erc20TokenAddress).burn(value);
    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) internal virtual {
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