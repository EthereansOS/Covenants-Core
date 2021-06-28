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
        IAMMAggregator aggregator = IAMMAggregator({0});
        {1}
        address[] memory ammsToAdd = new address[]({2});
        {3}
        if(ammsToAdd.length > 0) {
            aggregator.add(ammsToAdd);
        }
    }
}

interface IAMMAggregator {
    function remove(uint256) external;
    function add(address[] calldata) external;
}