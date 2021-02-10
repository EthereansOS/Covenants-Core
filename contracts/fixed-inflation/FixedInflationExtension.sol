//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./FixedInflationData.sol";
import "./IFixedInflationExtension.sol";
import "./util/IERC20.sol";
import "./util/IERC20Mintable.sol";
import "./IFixedInflation.sol";

contract FixedInflationExtension is IFixedInflationExtension {

    address private _host;

    address private _fixedInflationContract;

    bool public override active;

    modifier fixedInflationOnly() {
        require(_fixedInflationContract == msg.sender, "Unauthorized");
        _;
    }

    modifier hostOnly() {
        require(_host == msg.sender, "Unauthorized");
        _;
    }

    receive() external payable {
    }

    function init(address host) override public {
        require(_host == address(0), "Already init");
        require((_host = host) != address(0), "blank host");
        _fixedInflationContract = msg.sender;
    }

    function setHost(address host) public virtual override hostOnly {
        _host = host;
    }

    function data() view public override returns(address fixedInflationContract, address host) {
        return(_fixedInflationContract, _host);
    }

    function setActive(bool _active) public override virtual hostOnly {
        active = _active;
    }

    function receiveTokens(address[] memory tokenAddresses, uint256[] memory transferAmounts, uint256[] memory amountsToMint) public override fixedInflationOnly {
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            if(transferAmounts[i] > 0) {
                if(tokenAddresses[i] == address(0)) {
                    payable(msg.sender).transfer(transferAmounts[i]);
                    continue;
                }
                _safeTransfer(tokenAddresses[i], msg.sender, transferAmounts[i]);
            }
            if(amountsToMint[i] > 0) {
                _mintAndTransfer(tokenAddresses[i], msg.sender, amountsToMint[i]);
            }
        }
    }

    function setEntries(FixedInflationEntryConfiguration[] memory newEntries, FixedInflationOperation[][] memory operationSets) public override hostOnly {
        IFixedInflation(_fixedInflationContract).setEntries(newEntries, operationSets);
    }

    /** INTERNAL METHODS */

    function _mintAndTransfer(address erc20TokenAddress, address recipient, uint256 value) internal virtual {
        IERC20Mintable(erc20TokenAddress).mint(recipient, value);
    }

    /** @dev function used to safe transfer ERC20 tokens.
      * @param erc20TokenAddress address of the token to transfer.
      * @param to receiver of the tokens.
      * @param value amount of tokens to transfer.
     */
    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) internal virtual {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFER_FAILED');
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