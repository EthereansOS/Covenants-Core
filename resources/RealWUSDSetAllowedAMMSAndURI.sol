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
        AllowedAMM[] memory newAllowedAMMs = new AllowedAMM[]({1});
        {2}
        IUSDExtensionController({0}).setAllowedAMMs(newAllowedAMMs);
        IUSDExtensionController({0}).setCollectionUri("{3}");
        Index({4}).setCollectionUri("{5}");
        ILiquidityMiningFactory({6}).updateLiquidityFarmTokenCollectionURI("{7}");
    }
}

interface IUSDExtensionController {
    function setController(address newController) external;
    function setAllowedAMMs(AllowedAMM[] calldata) external;
    function setCollectionUri(string calldata) external;
}

struct AllowedAMM {
    address ammAddress;
    address[] liquidityPools;
}

interface Index {
    function setCollectionUri(string calldata) external;
}

interface ILiquidityMiningFactory {
    function updateLiquidityFarmTokenCollectionURI(string calldata) external;
}