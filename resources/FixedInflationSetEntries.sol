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
        FixedInflationEntryConfiguration[] memory newEntries = new FixedInflationEntryConfiguration[]({1});
        {2}
        FixedInflationOperation[][] memory operationSets = new FixedInflationOperation[][]({1});
        {3}
        IFixedInflationExtension({0}).setEntries(newEntries, operationSets);
    }

    {4}
}

interface IFixedInflationExtension {
    function setEntries(FixedInflationEntryConfiguration[] memory newEntries, FixedInflationOperation[][] memory operationSets) external;
}

struct FixedInflationEntryConfiguration {
    bool add;
    bool remove;
    FixedInflationEntry data;
}

struct FixedInflationEntry {
    uint256 lastBlock;
    bytes32 id;
    string name;
    uint256 blockInterval;
    uint256 callerRewardPercentage;
}

struct FixedInflationOperation {

    address inputTokenAddress;
    uint256 inputTokenAmount;
    bool inputTokenAmountIsPercentage;
    bool inputTokenAmountIsByMint;

    address ammPlugin;
    address[] liquidityPoolAddresses;
    address[] swapPath;
    bool enterInETH;
    bool exitInETH;

    address[] receivers;
    uint256[] receiversPercentages;
}