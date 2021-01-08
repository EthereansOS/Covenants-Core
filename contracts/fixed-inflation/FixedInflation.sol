//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;

import "./FixedInflationData.sol";
import "./IFixedInflationExtension.sol";
import "./util/IERC20.sol";

contract FixedInflation {

    struct FixedInflationEntry {
        uint256 lastBlock;
        uint256 blockInterval;

        address inputTokenAddress;
        uint256 inputTokenAmount;
        bool inputTokenByMint;

        address ammPlugin;
        address[] liquidityPools;
        address[][] swapPaths;

        address[] receivers;

        uint256 byEarnPercentage;

        uint256 rewardTokenAddress;
        uint256 rewardAmount;
        bool rewardByMint;
    }

    address public extension;

    FixedInflationEntry[] public entries;

    function init(address _extension, bytes memory extensionPayload, FixedInflationEntry[] memory _entries) public returns(bytes memory extensionInitResult) {
        require(extension == address(0), "Already init");
        require(_extension != address(0), "Blank extension");
        extension = _extension;
        if(keccak256(extensionPayload) != keccak256("")) {
            bool result;
            (result, extensionInitResult) = _extension.call(extensionPayload);
            require(result, "Extension fail");
        }
        require(_entries.length > 0, "Empty entries");
        _setEntries(_entries);
    }

    modifier extensionOnly() {
        require(msg.sender == extension, "Unauthorized");
        _;
    }

    function setEntries(FixedInflationEntry[] memory _entries) public extensionOnly {
        _setEntries(_entries);
    }

    function nextBlock(uint256 i) public view returns(uint256) {
        return entries[i].lastBlock == 0 ? block.number : (entries[i].lastBlock + entries[i].blockInterval);
    }

    function entriesLength() public view returns(uint256) {
        return entries.length;
    }

    function call(uint256[] memory indexes, bool[] memory byEarn) public {
        require(indexes.length > 0 && indexes.length == byEarn.length, "Invalid input data");
        for(uint256 i = 0; i < indexes.length; i++) {
            require(entries.length > indexes[i], "Invalid index");
            require(nextBlock(indexes[i]) >= block.number, "Too early to call index");
            _call(indexes[i], byEarn[i], msg.sender);
        }
    }

    function _call(uint256 i, bool byEarn, address rewardReceiver) private {
        FixedInflationEntry storage inflationEntry = entries[i];
        inflationEntry.lastBlock = block.number;
        require(!byEarn || inflationEntry.byEarnPercentage > 0, "Invalid byEarn");
        IFixedInflationExtension(extension).transfer
    }

    function _setEntries(FixedInflationEntry[] memory _entries) private {

    }

    function _safeApprove(address erc20TokenAddress, address to, uint256 value) internal virtual {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).approve.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'APPROVE_FAILED');
    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) internal virtual {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }

    function _safeTransferFrom(address erc20TokenAddress, address from, address to, uint256 value) internal virtual {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFERFROM_FAILED');
    }
}