// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

interface IERC20Mintable {
    function mint(address wallet, uint256 amount) external view returns (bool);
}
