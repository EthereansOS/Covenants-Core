//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./IFarmExtensionGen1.sol";
import "./IFarmMainGen1.sol";
import "./util/IERC20.sol";
import "./util/IERC20Mintable.sol";

contract FarmExtensionGen1 is IFarmExtensionGen1 {

    // wallet who has control on the extension and treasury
    address internal _host;
    address internal _treasury;
    // address of the farm main contract linked to this extension
    address internal _farmMainContract;
    // the reward token address linked to this extension
    address internal _rewardTokenAddress;
    // whether the token is by mint or by reserve
    bool internal _byMint;

    /** MODIFIERS */

    /** @dev farmMainOnly modifier used to check for unauthorized transfers. */
    modifier farmMainOnly() {
        require(msg.sender == _farmMainContract, "Unauthorized");
        _;
    }

    /** @dev hostOnly modifier used to check for unauthorized edits. */
    modifier hostOnly() {
        require(msg.sender == _host, "Unauthorized");
        _;
    }

    /** PUBLIC METHODS */

    receive() external payable {
        require(_farmMainContract != address(0) && _rewardTokenAddress == address(0), "ETH not allowed");
    }

    function init(bool byMint, address host, address treasury) public virtual override {
        require(_farmMainContract == address(0), "Already init");
        require((_host = host) != address(0), "blank host");
        _rewardTokenAddress = IFarmMainGen1(_farmMainContract = msg.sender)._rewardTokenAddress();
        _byMint = byMint;
        _treasury = treasury != address(0) ? treasury : host;
    }

    function data() view public virtual override returns(address farmMainContract, bool byMint, address host, address treasury, address rewardTokenAddress) {
        return (_farmMainContract, _byMint, _host, _treasury, _rewardTokenAddress);
    }

    /** @dev method used to update the extension host.
      * @param host new host address.
     */
    function setHost(address host) public virtual override hostOnly {
        _host = host;
    }

    /** @dev method used to update the extension treasury.
      * @param treasury new treasury address.
     */
    function setTreasury(address treasury) public virtual override hostOnly {
        _treasury = treasury;
    }

    /** @dev this function calls the farm main contract with the given address and sets the given farming setups.
      * @param farmingSetups array containing all the farming setups.
     */
    function setFarmingSetups(FarmingSetupConfiguration[] memory farmingSetups) public virtual override hostOnly {
        IFarmMainGen1(_farmMainContract).setFarmingSetups(farmingSetups);
    }

    /** @dev transfers the input amount to the caller farming contract.
      * @param amount amount of erc20 to transfer or mint.
     */
    function transferTo(uint256 amount) public virtual override farmMainOnly {
        if(_rewardTokenAddress != address(0)) {
            return _byMint ? _mintAndTransfer(_rewardTokenAddress, _farmMainContract, amount) : _safeTransfer(_rewardTokenAddress, _farmMainContract, amount);
        }
        (bool result, ) = _farmMainContract.call{value:amount}("");
        require(result, "ETH transfer failed.");
    }

    /** @dev transfers the input amount from the caller farming contract to the extension.
      * @param amount amount of erc20 to transfer back or burn.
     */
    function backToYou(uint256 amount) payable public virtual override farmMainOnly {
        if(_rewardTokenAddress != address(0)) {
            _safeTransferFrom(_rewardTokenAddress, msg.sender, _byMint ? address(this) : _treasury, amount);
            if(_byMint) {
                _burn(_rewardTokenAddress, amount);
            }
        } else {
            require(msg.value == amount, "invalid sent amount");
            if(_treasury != address(this)) {
                (bool result, ) = _treasury.call{value:amount}("");
                require(result, "ETH transfer failed.");
            }
        }
    }

    /** INTERNAL METHODS */

    function _mintAndTransfer(address erc20TokenAddress, address recipient, uint256 value) internal virtual {
        IERC20Mintable(erc20TokenAddress).mint(recipient, value);
    }

    function _burn(address erc20TokenAddress, uint256 value) internal virtual {
        IERC20Mintable(erc20TokenAddress).burn(msg.sender, value);
    }

    /** @dev function used to safely approve ERC20 transfers.
      * @param erc20TokenAddress address of the token to approve.
      * @param to receiver of the approval.
      * @param value amount to approve for.
     */
    function _safeApprove(address erc20TokenAddress, address to, uint256 value) internal virtual {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).approve.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'APPROVE_FAILED');
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

    /** @dev this function safely transfers the given ERC20 value from an address to another.
      * @param erc20TokenAddress erc20 token address.
      * @param from address from.
      * @param to address to.
      * @param value amount to transfer.
     */
    function _safeTransferFrom(address erc20TokenAddress, address from, address to, uint256 value) internal virtual {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).transferFrom.selector, from, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFERFROM_FAILED');
    }

    /** @dev calls the contract at the given location using the given payload and returns the returnData.
      * @param location location to call.
      * @param payload call payload.
      * @return returnData call return data.
     */
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