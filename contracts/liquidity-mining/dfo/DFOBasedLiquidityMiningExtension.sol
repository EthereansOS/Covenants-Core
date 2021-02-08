//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../ILiquidityMiningExtension.sol";
import "../ILiquidityMining.sol";
import "../util/IERC20.sol";
import "../LiquidityMiningData.sol";
import "../util/DFOHub.sol";

contract DFOBasedLiquidityMiningExtension is ILiquidityMiningExtension {

    string private constant FUNCTIONALITY_NAME = "manageLiquidityMining";

    // wallet who has control on the extension
    address internal _doubleProxy;

    // mapping that contains all the liquidity mining contract linked to this extension
    address internal _liquidityMiningContract;

    // the reward token address linked to this liquidity mining contract
    address internal _rewardTokenAddress;

    // whether the token is by mint or by reserve
    bool internal _byMint;

    bool public override active;

    /** MODIFIERS */

    /** @dev liquidityMiningOnly modifier used to check for unauthorized transfers. */
    modifier liquidityMiningOnly() {
        require(msg.sender == _liquidityMiningContract, "Unauthorized");
        _;
    }

    /** @dev hostOnly modifier used to check for unauthorized edits. */
    modifier hostOnly() {
        require(_isFromDFO(msg.sender), "Unauthorized");
        _;
    }

    /** PUBLIC METHODS */

    function init(bool byMint, address host) public virtual override {
        require(_liquidityMiningContract == address(0), "Already init");
        require((_doubleProxy = host) != address(0), "blank host");
        _rewardTokenAddress = ILiquidityMining(_liquidityMiningContract = msg.sender)._rewardTokenAddress();
        _byMint = byMint;
    }

    function setActive(bool _active) public virtual hostOnly {
        active = _active;
    }

    /** @dev allows the DFO to update the double proxy address.
      * @param newDoubleProxy new double proxy address.
     */
    function setHost(address newDoubleProxy) public virtual override hostOnly {
        _doubleProxy = newDoubleProxy;
    }

    function data() view public virtual override returns(address liquidityMiningContract, bool byMint, address host, address rewardTokenAddress) {
        return (_liquidityMiningContract, _byMint, _doubleProxy, _rewardTokenAddress);
    }

    /** @dev transfers the input amount to the caller liquidity mining contract.
      * @param amount amount of erc20 to transfer or mint.
     */
    function transferTo(uint256 amount, address recipient) override public liquidityMiningOnly {
        IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).submit(FUNCTIONALITY_NAME, abi.encode(address(0), 0, true, _rewardTokenAddress, recipient, amount, _byMint));
    }

    /** @dev transfers the input amount from the caller liquidity mining contract to the extension.
      * @param amount amount of erc20 to transfer back or burn.
     */
    function backToYou(uint256 amount) override payable public liquidityMiningOnly {
        if(_rewardTokenAddress != address(0)) {
            _safeTransferFrom(_rewardTokenAddress, msg.sender, address(this), amount);
            _safeApprove(_rewardTokenAddress, _getFunctionalityAddress(), amount);
            IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).submit(FUNCTIONALITY_NAME, abi.encode(address(0), 0, false, _rewardTokenAddress, msg.sender, amount, _byMint));
        } else {
            IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).submit{value : amount}(FUNCTIONALITY_NAME, abi.encode(address(0), 0, false, _rewardTokenAddress, msg.sender, amount, _byMint));
        }
    }

    /** @dev this function calls the liquidity mining contract with the given address and sets the given liquidity mining setups.
      * @param liquidityMiningSetups array containing all the liquidity mining setups.
      * @param setPinned if we're updating the pinned setup or not.
      * @param pinnedIndex new pinned setup index.
     */
    function setLiquidityMiningSetups(LiquidityMiningSetupConfiguration[] memory liquidityMiningSetups, bool clearPinned, bool setPinned, uint256 pinnedIndex) public override hostOnly {
        ILiquidityMining(_liquidityMiningContract).setLiquidityMiningSetups(liquidityMiningSetups, clearPinned, setPinned, pinnedIndex);
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