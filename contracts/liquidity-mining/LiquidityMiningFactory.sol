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
      * @param _liquidityMiningImplementationAddress liquidity mining contract address for logic and cloning purposes.
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
        bytes20 logic = bytes20(liquidityMiningImplementationAddress);
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), logic)
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            contractAddress := create(0, clone, 0x37)
        }
        emit LiquidityMiningDeployed(msg.sender, contractAddress);
        if (data.length > 0) {
            (bool initSuccess,) = contractAddress.call(data);
            require(initSuccess);
        }
    }

}