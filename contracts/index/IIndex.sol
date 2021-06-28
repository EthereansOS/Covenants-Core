//SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

interface IIndex {

    function _doubleProxy() external view returns(address);

    function collection() external view returns(address);

    function setDoubleProxy(address newDoubleProxy) external;

    function setCollectionUri(string calldata uri) external;

    function info(uint256 objectId, uint256 value) external view returns(address[] memory _tokens, uint256[] memory _amounts);

    function mint(string calldata name, string calldata symbol, string calldata uri, address[] calldata _tokens, uint256[] calldata _amounts, uint256 value, address receiver) external payable returns(uint256 objectId, address interoperableInterfaceAddress);

    function mint(uint256 objectId, uint256 value, address receiver) external payable;
}