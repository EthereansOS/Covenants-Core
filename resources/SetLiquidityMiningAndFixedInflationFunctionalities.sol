// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

contract ProposalCode {

    string private _metadataLink;

    constructor(string memory metadataLink) {
        _metadataLink = metadataLink;
    }

    function getMetadataLink() public view returns(string memory) {
        return _metadataLink;
    }

    function onStart(address, address) public {
    }

    function onStop(address) public {
    }

    function callOneTime(address) public {
        IMVDFunctionalitiesManager functionalitiesManager = IMVDFunctionalitiesManager(IMVDProxy(msg.sender).getMVDFunctionalitiesManagerAddress());
        functionalitiesManager.addFunctionality("manageFixedInflation", address(0), 0, {0}, true, "manageFixedInflation(address,uint256,address[],uint256[],uint256[],address)", "[]", false, true);
        functionalitiesManager.addFunctionality("manageFixedInflation", address(0), 0, {1}, true, "manageFixedInflation(address,uint256,address[],uint256[],uint256[],address)", "[]", false, true);
    }
}

interface IMVDProxy {
    function getMVDFunctionalitiesManagerAddress() external view returns(address);
}

interface IMVDFunctionalitiesManager {
    function addFunctionality(string calldata codeName, address sourceLocation, uint256 sourceLocationId, address location, bool submitable, string calldata methodSignature, string calldata returnAbiParametersArray, bool isInternal, bool needsSender) external;
}