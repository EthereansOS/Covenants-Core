//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "../../contracts/farming/FarmExtension.sol";

contract OSFarmExtension is FarmExtension {

    address public osMinterAddress;

    function init(bool byMint, address host, address treasury, address _osMinterAddress) public {
        super.init(byMint, host, treasury);
        osMinterAddress = _osMinterAddress;
    }

    function init(bool, address, address) public virtual override {
        revert("use specific method if not already init");
    }

    function _mintAndTransfer(address, address recipient, uint256 value) internal override {
        IERC20Mintable(osMinterAddress).mint(recipient, value);
    }
}