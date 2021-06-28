// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

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
        IWUSDExtensionController controller = IWUSDExtensionController({0});
        controller.setrebalanceByCreditBlockInterval({1});
        address[] memory rebalanceByCreditReceivers = new address[]({2});
        {3}
        uint256[] memory rebalanceByCreditPercentages = new uint256[]({2});
        {4}
        controller.setRebalanceByCreditData(rebalanceByCreditReceivers, rebalanceByCreditPercentages, {5});
    }
}

interface IWUSDExtensionController {
    function setrebalanceByCreditBlockInterval(uint256 newrebalanceByCreditBlockInterval) external;
    function setRebalanceByCreditData(address[] memory rebalanceByCreditReceivers, uint256[] memory rebalanceByCreditPercentages, uint256 rebalanceByCreditPercentageForCaller) external;
}