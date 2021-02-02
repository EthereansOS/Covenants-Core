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
        ILiquidityMiningFactory({0}).updateLiquidityFarmTokenCollectionURI("{1}");
        ILiquidityMiningFactory({0}).updateLiquidityFarmTokenURI("{2}");
    }
}

interface ILiquidityMiningFactory {
    function updateLiquidityFarmTokenCollectionURI(string memory liquidityFarmTokenCollectionUri) external;
    function updateLiquidityFarmTokenURI(string memory liquidityFarmTokenUri) external;
}