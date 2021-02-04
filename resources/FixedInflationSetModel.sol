// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
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
        IFixedInflationFactory({0}).updateLogicAddress({1});
    }
}

interface IFixedInflationFactory {
    function updateLogicAddress(address _fixedInflationImplementationAddress) external;
}