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
        FixedInflationOperation[] memory operationSets = new FixedInflationOperation[]({2});
        {3}
        IFixedInflationExtension({0}).setEntry({1}, operationSets);
    }

    {4}
}

interface IFixedInflationExtension {
    function setEntry(FixedInflationEntry memory entryData, FixedInflationOperation[] memory operations) external;
}

struct FixedInflationEntry {
    string name;
    uint256 blockInterval;
    uint256 lastBlock;
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