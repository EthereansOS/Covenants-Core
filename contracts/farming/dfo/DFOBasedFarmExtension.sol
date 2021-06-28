//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "../IFarmExtension.sol";
import "../IFarmMain.sol";
import "../util/IERC20.sol";
import "../util/DFOHub.sol";

contract DFOBasedFarmExtension is IFarmExtension {

    string private constant FUNCTIONALITY_NAME = "manageFarming";

    // wallet who has control on the extension
    address internal _doubleProxy;

    // mapping that contains all the farming contract linked to this extension
    address internal _farmingContract;

    // the reward token address linked to this farming contract
    address internal _rewardTokenAddress;

    // whether the token is by mint or by reserve
    bool internal _byMint;

    /** MODIFIERS */

    /** @dev farmingOnly modifier used to check for unauthorized transfers. */
    modifier farmingOnly() {
        require(msg.sender == _farmingContract, "Unauthorized");
        _;
    }

    /** @dev hostOnly modifier used to check for unauthorized edits. */
    modifier hostOnly() {
        require(_isFromDFO(msg.sender), "Unauthorized");
        _;
    }

    /** PUBLIC METHODS */

    function init(bool byMint, address host, address) public virtual override {
        require(_farmingContract == address(0), "Already init");
        require((_doubleProxy = host) != address(0), "blank host");
        _rewardTokenAddress = IFarmMain(_farmingContract = msg.sender)._rewardTokenAddress();
        _byMint = byMint;
    }

    /** @dev allows the DFO to update the double proxy address.
      * @param newDoubleProxy new double proxy address.
     */
    function setHost(address newDoubleProxy) public virtual override hostOnly {
        _doubleProxy = newDoubleProxy;
    }

    /** @dev method used to update the extension treasury.
     */
    function setTreasury(address) public virtual override hostOnly {
        revert("Impossibru!");
    }

    function data() view public virtual override returns(address farmingContract, bool byMint, address host, address treasury, address rewardTokenAddress) {
        return (_farmingContract, _byMint, _doubleProxy, IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDWalletAddress(), _rewardTokenAddress);
    }

    /** @dev transfers the input amount to the caller farming contract.
      * @param amount amount of erc20 to transfer or mint.
     */
    function transferTo(uint256 amount) override public farmingOnly {
        IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).submit(FUNCTIONALITY_NAME, abi.encode(address(0), 0, true, _rewardTokenAddress, _farmingContract, amount, _byMint));
    }

    /** @dev transfers the input amount from the caller farming contract to the extension.
      * @param amount amount of erc20 to transfer back or burn.
     */
    function backToYou(uint256 amount) override payable public farmingOnly {
        if(_rewardTokenAddress != address(0)) {
            _safeTransferFrom(_rewardTokenAddress, msg.sender, address(this), amount);
            _safeApprove(_rewardTokenAddress, _getFunctionalityAddress(), amount);
            IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).submit(FUNCTIONALITY_NAME, abi.encode(address(0), 0, false, _rewardTokenAddress, msg.sender, amount, _byMint));
        } else {
            IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).submit{value : amount}(FUNCTIONALITY_NAME, abi.encode(address(0), 0, false, _rewardTokenAddress, msg.sender, amount, _byMint));
        }
    }

    /** @dev this function calls the farming contract with the given address and sets the given farming setups.
      * @param farmingSetups array containing all the farming setups.
     */
    function setFarmingSetups(FarmingSetupConfiguration[] memory farmingSetups) public override hostOnly {
        IFarmMain(_farmingContract).setFarmingSetups(farmingSetups);
    }

    /** PRIVATE METHODS */

    /** @dev this function returns the address of the functionality with the FUNCTIONALITY_NAME.
      * @return functionalityAddress functionality FUNCTIONALITY_NAME address.
     */
    function _getFunctionalityAddress() private view returns(address functionalityAddress) {
        (functionalityAddress,,,,) = IMVDFunctionalitiesManager(IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDFunctionalitiesManagerAddress()).getFunctionalityData(FUNCTIONALITY_NAME);
    }

    /** @dev this function returns the address of the wallet of the linked DFO.
      * @return linked DFO wallet address.
     */
    function _getDFOWallet() private view returns(address) {
        return IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDWalletAddress();
    }

    /** @dev this function returns true if the sender is an authorized DFO functionality, false otherwise.
      * @param sender address of the caller.
      * @return true if the call is from a DFO, false otherwise.
     */
    function _isFromDFO(address sender) private view returns(bool) {
        return IMVDFunctionalitiesManager(IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDFunctionalitiesManagerAddress()).isAuthorizedFunctionality(sender);
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

    /** @dev this function safely transfers the given ERC20 value from an address to another.
      * @param erc20TokenAddress erc20 token address.
      * @param from address from.
      * @param to address to.
      * @param value amount to transfer.
     */
    function _safeTransferFrom(address erc20TokenAddress, address from, address to, uint256 value) private {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).transferFrom.selector, from, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFERFROM_FAILED');
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