//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

contract LiquidityMiningFactory {
    
    // liquidity mining contract implementation address
    address public liquidityMiningImplementationAddress;
    // factory owner address (needed?)
    address private factoryOwner;

    // event that tracks liquidity mining contracts deployed
    event LiquidityMiningDeployed(address indexed owner, address indexed contractAddress);
    // event that tracks logic contract address change
    event LiquidityMiningLogicChanged(address oldAddress, address newAddress);

    /** @dev creates a new liquidity mining factory instance.
      * @param _factoryOwner owner of this factory contract (or msg.sender if address(0) is provided).
      * @param _liquidityMiningImplementationAddress liquidity mining implementation address.
     */
    constructor(address _factoryOwner, address _liquidityMiningImplementationAddress) {
        if (_factoryOwner == address(0)) {
            _factoryOwner = msg.sender;
        }
        factoryOwner = _factoryOwner;
        liquidityMiningImplementationAddress = _liquidityMiningImplementationAddress;
    }

    /** @dev onlyOwner modifier used to check for unauthorized changes. */
    modifier onlyOwner {
        require(msg.sender == factoryOwner, "Unauthorized.");
        _;
    }

    /** @dev allows the factory owner to update the logic contract address.
      * @param _liquidityMiningImplementationAddress new liquidity mining implementation address.
     */
    function updateLogicAddress(address _liquidityMiningImplementationAddress) public onlyOwner {
        emit LiquidityMiningLogicChanged(liquidityMiningImplementationAddress, _liquidityMiningImplementationAddress);
        liquidityMiningImplementationAddress = _liquidityMiningImplementationAddress;
    }

    /** @dev this function deploys a new LiquidityMining contract and calls the encoded function passed as data.
      * @param data encoded initialize function for the liquidity mining contract (check LiquidityMining contract code).
      * @return contractAddress new liquidity mining contract address.
     */
    function deploy(bytes memory data) public returns (address contractAddress) {
        (bool initSuccess,) = (contractAddress = _clone(liquidityMiningImplementationAddress)).call(data);
        require(initSuccess, "Error while creating new liquidity mining contract");
        emit LiquidityMiningDeployed(msg.sender, contractAddress);
    }

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
}