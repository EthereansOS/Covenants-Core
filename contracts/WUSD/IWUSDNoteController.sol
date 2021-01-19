//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "./util/INativeV1.sol";

interface IWUSDNoteController {

    function wusdCollection() external view returns(address);
    function wusdObjectId() external view returns(uint256);
    function wusdNoteObjectId() external view returns(uint256);
    function multiplier() external view returns(uint256);

    function info() external view returns(address, uint256, uint256, uint256);

    function init(address _wusdCollection, uint256 _wusdObjectId, uint256 _wusdNoteObjectId, uint256 _multiplier) external;
}