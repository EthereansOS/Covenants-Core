//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./ILiquidityMiningExtension.sol";
import "./ILiquidityMining.sol";
import "./util/IERC20.sol";
import "./util/IERC20Mintable.sol";

contract LiquidityMiningExtension is ILiquidityMiningExtension {

    // factory address that creates the liquidity mining contracts
    address public _factory;
    // double proxy address of the linked DFO
    address private _doubleProxy;
    // mapping that contains all the liquidity mining contracts linked to this extension
    mapping(address => bool) private _liquidityMiningContracts;

    constructor(address factory) {
        _factory = factory;
    }

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

    /** @dev function called by the factory to add a new liquidity mining contract to the extension.
      * @param liquidityMiningAddress new liquidity mining address to set.
     */
    function addLiquidityMiningContract(address liquidityMiningAddress) override public {
        require(msg.sender == _factory, "Unauthorized.");
        _liquidityMiningContracts[liquidityMiningAddress] = true;
    }

    /** @dev transfers the input amount from the caller liquidity mining contract to the extension.
      * @param amount amount of erc20 to transfer back or burn.
      * @return true if everything was ok, false otherwise.
     */
    function backToYou(uint256 amount) override public onlyLiquidityMining returns(bool) {        
        (address rewardTokenAddress, bool byMint) = ILiquidityMining(msg.sender).getRewardTokenData();
        if (byMint) {
            return IERC20Mintable(rewardTokenAddress).burn(msg.sender, amount);
        } else {
            _safeTransferFrom(rewardTokenAddress, msg.sender, _getDFOWallet(), amount);
            return true;
        }
    }

    /** @dev allows the DFO to update the double proxy address.
      * @param newDoubleProxy new double proxy address.
     */
    function setDoubleProxy(address newDoubleProxy) public onlyDFO {
        _doubleProxy = newDoubleProxy;
    }

    /** @dev allows the DFO to update the factory address.
      * @param newFactory new factory address.
     */
    function setFactory(address newFactory) public onlyDFO {
        _factory = newFactory;
    }

    /** @dev transfers the input amount to the caller liquidity mining contract.
      * @param amount amount of erc20 to transfer or mint.
      * @return true if everything was ok, false otherwise.
     */
    function transferMe(uint256 amount) override public onlyLiquidityMining returns(bool) {
        (address rewardTokenAddress, bool byMint) = ILiquidityMining(msg.sender).getRewardTokenData();
        if (byMint) {
            return IERC20Mintable(rewardTokenAddress).mint(msg.sender, amount);
        } else {
            _safeTransferFrom(rewardTokenAddress, _getDFOWallet(), msg.sender, amount);
            return true;
        }
    }

    /** PRIVATE METHODS */

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

    /** @dev this function safely transfers the given ERC20 value from an address to another.
      * @param erc20TokenAddress erc20 token address.
      * @param from address from.
      * @param to address to.
      * @param value amount to transfer.
     */
    function _safeTransferFrom(address erc20TokenAddress, address from, address to, uint256 value) private {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFERFROM_FAILED');
    }
}