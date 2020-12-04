//SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "./IEthItem.sol";

interface IERC20WrapperV1 is IEthItem {

    function source(uint256 objectId) external view returns (address erc20TokenAddress);

    function object(address erc20TokenAddress) external view returns (uint256 objectId);

    function mint(address erc20TokenAddress, uint256 amount, string calldata tokenUri) external returns (uint256 objectId, address wrappedTokenAddress);
}
