//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./util/DFOHub.sol";
import "./ILiquidityMiningFactory.sol";

contract LiquidityMiningFactory is ILiquidityMiningFactory {

    // liquidity mining contract implementation address
    address public liquidityMiningImplementationAddress;

    // liquidity mining default extension
    address public override liquidityMiningDefaultExtension;

    // double proxy address of the linked DFO
    address public _doubleProxy;

    // linked DFO exit fee
    uint256 private _feePercentage;

    // event that tracks liquidity mining contracts deployed
    event LiquidityMiningDeployed(address indexed liquidityMiningAddress, address indexed sender, bytes liquidityMiningInitResultData);

    // event that tracks logic contract address change
    event LiquidityMiningLogicSet(address indexed newAddress);

    // event that tracks default extension contract address change
    event LiquidityMiningDefaultExtensionSet(address indexed newAddress);

    // event that tracks wallet changes
    event FeePercentageSet(uint256 newFeePercentage);

    constructor(address doubleProxy, address _liquidityMiningImplementationAddress, address _liquidityMiningDefaultExtension, uint256 feePercentage) {
        _doubleProxy = doubleProxy;
        emit LiquidityMiningLogicSet(liquidityMiningImplementationAddress = _liquidityMiningImplementationAddress);
        emit LiquidityMiningDefaultExtensionSet(liquidityMiningDefaultExtension = _liquidityMiningDefaultExtension);
        emit FeePercentageSet(_feePercentage = feePercentage);
    }

    /** PUBLIC METHODS */

    function feePercentageInfo() public override view returns (uint256, address) {
        return (_feePercentage, IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDWalletAddress());
    }

    /** @dev allows the DFO to update the double proxy address.
      * @param newDoubleProxy new double proxy address.
    */
    function setDoubleProxy(address newDoubleProxy) public onlyDFO {
        _doubleProxy = newDoubleProxy;
    }

    /** @dev change the fee percentage
     * @param feePercentage new fee percentage.
     */
    function updateFeePercentage(uint256 feePercentage) public onlyDFO {
        emit FeePercentageSet(_feePercentage = feePercentage);
    }

    /** @dev allows the factory owner to update the logic contract address.
     * @param _liquidityMiningImplementationAddress new liquidity mining implementation address.
     */
    function updateLogicAddress(address _liquidityMiningImplementationAddress) public onlyDFO {
        emit LiquidityMiningLogicSet(liquidityMiningImplementationAddress = _liquidityMiningImplementationAddress);
    }

    /** @dev allows the factory owner to update the default extension contract address.
     * @param _liquidityMiningDefaultExtensionAddress new liquidity mining extension address.
     */
    function updateDefaultExtensionAddress(address _liquidityMiningDefaultExtensionAddress) public onlyDFO {
        emit LiquidityMiningDefaultExtensionSet(liquidityMiningDefaultExtension = _liquidityMiningDefaultExtensionAddress);
    }

    /** @dev this function deploys a new LiquidityMining contract and calls the encoded function passed as data.
     * @param data encoded initialize function for the liquidity mining contract (check LiquidityMining contract code).
     * @return contractAddress new liquidity mining contract address.
     * @return initResultData new liquidity mining contract call result.
     */
    function deploy(bytes memory data) public returns (address contractAddress, bytes memory initResultData) {
        initResultData = _call(contractAddress = _clone(liquidityMiningImplementationAddress), data);
        emit LiquidityMiningDeployed(contractAddress, msg.sender, initResultData);
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

    /** @dev onlyDFO modifier used to check for unauthorized accesses. */
    modifier onlyDFO() {
        require(IMVDFunctionalitiesManager(IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDFunctionalitiesManagerAddress()).isAuthorizedFunctionality(msg.sender), "Unauthorized.");
        _;
    }
}