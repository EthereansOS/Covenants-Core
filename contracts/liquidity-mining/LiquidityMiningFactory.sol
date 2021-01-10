//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./util/DFOHub.sol";

contract LiquidityMiningFactory {

    // liquidity mining contract implementation address
    address public liquidityMiningImplementationAddress;
    // double proxy address of the linked DFO
    address private _doubleProxy;
    // owner wallet (UniFi)
    address public _wallet;
    // owner wallet exit fee
    uint256 public _exitFee;

    // event that tracks wallet changes
    event ExitFeeChanged(uint256 oldValue, uint256 newValue);
    // event that tracks liquidity mining contracts deployed
    event LiquidityMiningDeployed(address indexed owner, address indexed contractAddress);
    // event that tracks logic contract address change
    event LiquidityMiningLogicChanged(address oldAddress, address newAddress);
    // event that tracks wallet changes
    event WalletChanged(address oldAddress, address newAddress);

    constructor(address doubleProxy, address _liquidityMiningImplementationAddress) {
        _doubleProxy = doubleProxy;
        liquidityMiningImplementationAddress = _liquidityMiningImplementationAddress;
    }

    /** PUBLIC METHODS */

    /** @dev this function deploys a new LiquidityMining contract and calls the encoded function passed as data.
      * @param data encoded initialize function for the liquidity mining contract (check LiquidityMining contract code).
      * @return contractAddress new liquidity mining contract address.
     */
    function deploy(bytes memory data) public returns (address contractAddress) {
        (bool initSuccess,) = (contractAddress = _clone(liquidityMiningImplementationAddress)).call(data);
        require(initSuccess, "Error while creating new liquidity mining contract");
        emit LiquidityMiningDeployed(msg.sender, contractAddress);
    }

    /** @dev allows the owner to update the exit fee.
      * @param newExitFee new exit fee value.
      */
    function updateExitFee(uint256 newExitFee) public onlyDFO {
        emit ExitFeeChanged(_exitFee, newExitFee);
        _exitFee = newExitFee;
    }

    /** @dev allows the factory owner to update the logic contract address.
      * @param _liquidityMiningImplementationAddress new liquidity mining implementation address.
     */
    function updateLogicAddress(address _liquidityMiningImplementationAddress) public onlyDFO {
        emit LiquidityMiningLogicChanged(liquidityMiningImplementationAddress, _liquidityMiningImplementationAddress);
        liquidityMiningImplementationAddress = _liquidityMiningImplementationAddress;
    }

    /** @dev allows the owner to update the wallet.
      * @param newWallet new wallet address.
      */
    function updateWallet(address newWallet) public onlyDFO {
        emit WalletChanged(_wallet, newWallet);
        _wallet = newWallet;
    }

    /** PRIVATE METHODS */

    /** @dev clones the input contract address and returns the copied contract address.
      * @param original address of the original contract.
      * @return copy copied contract address.
     */
    function _clone(address original) private returns (address copy) {
        assembly {
            mstore(
                0,
                or(
                    0x5880730000000000000000000000000000000000000000803b80938091923cF3,
                    mul(original, 0x1000000000000000000)
                )
            )
            copy := create(0, 0, 32)
            switch extcodesize(copy)
                case 0 {
                    invalid()
                }
        }
    }

    /** @dev onlyDFO modifier used to check for unauthorized accesses. */
    modifier onlyDFO() {
        require(_isFromDFO(msg.sender), "Unauthorized.");
        _;
    }

    /** @dev allows the DFO to update the double proxy address.
      * @param newDoubleProxy new double proxy address.
     */
    function setDoubleProxy(address newDoubleProxy) public onlyDFO {
        _doubleProxy = newDoubleProxy;
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
}