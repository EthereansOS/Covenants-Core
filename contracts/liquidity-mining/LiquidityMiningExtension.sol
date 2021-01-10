//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./ILiquidityMiningExtension.sol";
import "./ILiquidityMining.sol";
import "./util/IERC20.sol";
import "./util/IERC20Mintable.sol";
import "./LiquidityMiningData.sol";

contract LiquidityMiningExtension is ILiquidityMiningExtension {

    string private constant FUNCTIONALITY_NAME = "manageLiquidityMining";

    // double proxy address of the linked DFO
    address private _doubleProxy;
    // mapping that contains all the liquidity mining contracts linked to this extension
    mapping(address => bool) private _liquidityMiningContracts;

    // whether the token is by mint or by reserve
    bool public _byMint;

    /** MODIFIERS */

    /** @dev onlyLiquidityMining modifier used to check for unauthorized transfers. */
    modifier onlyLiquidityMining() {
        require(_liquidityMiningContracts[msg.sender], "Unauthorized.");
        _;
    }

    /** @dev onlyDFO modifier used to check for unauthorized accesses. */
    modifier onlyDFO() {
        require(_isFromDFO(msg.sender), "Unauthorized.");
        _;
    }

    /** PUBLIC METHODS */

    function init(address doubleProxyAddress, bool byMint) override public {
        require(_doubleProxy == address(0), "Init already called!");
        _doubleProxy = doubleProxyAddress;
        _byMint = byMint;
        _liquidityMiningContracts[msg.sender] = true;
    }

    /** @dev transfers the input amount from the caller liquidity mining contract to the extension.
      * @param amount amount of erc20 to transfer back or burn.
     */
    function backToYou(uint256 amount) override payable public onlyLiquidityMining {
        address rewardTokenAddress = ILiquidityMining(msg.sender)._rewardTokenAddress();
        if(rewardTokenAddress != address(0)) {
            _safeTransferFrom(rewardTokenAddress, msg.sender, address(this), amount);
            _safeApprove(rewardTokenAddress, _getFunctionalityAddress(), amount);
            IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).submit(FUNCTIONALITY_NAME, abi.encode(address(0), 0, false, rewardTokenAddress, msg.sender, amount, _byMint));
        } else {
            IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).submit{value : amount}(FUNCTIONALITY_NAME, abi.encode(address(0), 0, false, rewardTokenAddress, msg.sender, amount, _byMint));
        }
    }

    /** @dev allows the DFO to update the double proxy address.
      * @param newDoubleProxy new double proxy address.
     */
    function setDoubleProxy(address newDoubleProxy) public onlyDFO {
        _doubleProxy = newDoubleProxy;
    }

    /** @dev this function calls the liquidity mining contract with the given address and sets the given liquidity mining setups.
      * @param liquidityMiningSetups array containing all the liquidity mining setups.
      * @param liquidityMiningContractAddress address of the liquidity mining contract.
      * @param setPinned if we're updating the pinned setup or not.
      * @param pinnedIndex new pinned setup index.
     */
    function setLiquidityMiningSetups(address liquidityMiningContractAddress, LiquidityMiningSetupConfiguration[] memory liquidityMiningSetups, bool clearPinned, bool setPinned, uint256 pinnedIndex) public override {
        require(_liquidityMiningContracts[liquidityMiningContractAddress], "Invalid liquidity mining contract.");
        ILiquidityMining(liquidityMiningContractAddress).setLiquidityMiningSetups(liquidityMiningSetups, clearPinned, setPinned, pinnedIndex);
    }

    /** @dev transfers the input amount to the caller liquidity mining contract.
      * @param amount amount of erc20 to transfer or mint.
     */
    function transferTo(uint256 amount, address recipient) override public onlyLiquidityMining {
        IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).submit(FUNCTIONALITY_NAME, abi.encode(address(0), 0, true, ILiquidityMining(msg.sender)._rewardTokenAddress(), recipient, amount, _byMint));
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

    /** this function safely approves the transfer of the ERC20 token with the given address.
      * @param erc20TokenAddress erc20 token address.
      * @param to address to.
      * @param value amount to transfer.
     */
    function _safeApprove(address erc20TokenAddress, address to, uint256 value) internal virtual {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).approve.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'APPROVE_FAILED');
    }

    /** @dev this function safely transfers the given ERC20 value from an address to another.
      * @param erc20TokenAddress erc20 token address.
      * @param from address from.
      * @param to address to.
      * @param value amount to transfer.
     */
    function _safeTransferFrom(address erc20TokenAddress, address from, address to, uint256 value) internal virtual {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFERFROM_FAILED');
    }
}