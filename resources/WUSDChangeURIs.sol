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
        IWUSDExtensionController({0}).setCollectionUri("{1}");
        IWUSDExtensionController({0}).setItemUri({2}, "{1}");
    }
}

interface IWUSDExtensionController {
    function setCollectionUri(string memory uri) external;
    function setItemUri(uint256 existingObjectId, string memory uri) external;
}