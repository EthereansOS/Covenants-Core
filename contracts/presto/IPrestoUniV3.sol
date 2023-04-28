//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./PrestoDataUniV3.sol";

interface IPrestoUniV3 {

    function ONE_HUNDRED() external view returns (uint256);
    function doubleProxy() external view returns (address);
    function feePercentage() external view returns (uint256);

    function feePercentageInfo() external view returns (uint256, address);

    function setDoubleProxy(address _doubleProxy) external;

    function setFeePercentage(uint256 _feePercentage) external;

    function execute(PrestoOperation[] memory operations) external payable returns(uint256[] memory outputAmounts);
}