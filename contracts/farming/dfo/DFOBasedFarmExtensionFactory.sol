//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "../util/DFOHub.sol";

contract DFOBasedFarmExtensionFactory {

    address public doubleProxy;

    address public model;

    event ExtensionCloned(address indexed extensionAddress, address indexed sender);

    constructor(address doubleProxyAddress, address modelAddress) {
        doubleProxy = doubleProxyAddress;
        model = modelAddress;
    }

    function setDoubleProxy(address doubleProxyAddress) public onlyDFO {
        doubleProxy = doubleProxyAddress;
    }

    function setModel(address modelAddress) public onlyDFO {
        model = modelAddress;
    }

    function cloneModel() public returns(address clonedExtension) {
        emit ExtensionCloned(clonedExtension = _clone(model), msg.sender);
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

    modifier onlyDFO() {
        require(IMVDFunctionalitiesManager(IMVDProxy(IDoubleProxy(doubleProxy).proxy()).getMVDFunctionalitiesManagerAddress()).isAuthorizedFunctionality(msg.sender), "Unauthorized.");
        _;
    }
}