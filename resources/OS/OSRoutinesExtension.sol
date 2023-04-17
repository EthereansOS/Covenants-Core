//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "../../contracts/routines/impl/RoutinesExtension.sol";

contract OSRoutinesExtension is RoutinesExtension {

    address public osMinterAddress;

    function init(address host, address _osMinterAddress) public {
        super.init(host);
        osMinterAddress = _osMinterAddress;
    }

    function init(address) public override {
        revert("use specific method if not already init");
    }

    function _mintAndTransfer(address, address recipient, uint256 value) internal override {
        IERC20Mintable(osMinterAddress).mint(recipient, value);
    }
}