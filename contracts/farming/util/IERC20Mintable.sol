// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IERC20Mintable {
    function mint(address wallet, uint256 amount) external returns (bool);
    function burn(address wallet, uint256 amount) external returns (bool);
}
