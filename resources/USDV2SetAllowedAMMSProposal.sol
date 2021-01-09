// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
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
        AllowedAMM[] memory newAllowedAMMs = new AllowedAMM[]({1});
        {2}
        IUSDExtensionController({0}).setAllowedAMMs(newAllowedAMMs);
    }
}

interface IUSDExtensionController {
    function setController(address newController) external;
    function setAllowedAMMs(AllowedAMM[] memory newAllowedAMMs) external;
}

struct AllowedAMM {
    address ammAddress;
    address[] liquidityPools;
}