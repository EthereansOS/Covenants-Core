// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

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
        IUSDExtensionController({0}).setController({1});
    }
}

interface IUSDExtensionController {
    function setController(address newController) external;
}