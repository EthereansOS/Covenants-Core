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
        IMVDProxy proxy = IMVDProxy(msg.sender);
        IStateHolder stateHolder = IStateHolder(proxy.getStateHolderAddress());
        stateHolder.setBool(_toStateHolderKey("fixedinflation.authorized", _toString({0})), true);
    }

    function onStop(address) public {
    }

    function manageFixedInflation(address sender, uint256, address[] memory tokenAddresses, uint256[] memory transferAmounts, uint256[] memory amountsToMint, address to) public {
        IMVDProxy proxy = IMVDProxy(msg.sender);
        IStateHolder stateHolder = IStateHolder(proxy.getStateHolderAddress());
        require(stateHolder.getBool(_toStateHolderKey("fixedinflation.authorized", _toString(sender))), "Unauthorized action");
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            IERC20 token = IERC20(tokenAddresses[i]);
            if(amountsToMint[i] > 0) {
                uint256 lastAmount = token.balanceOf(msg.sender);
                token.mint(amountsToMint[i]);
                proxy.flushToWallet(address(token), false, 0);
                if(lastAmount > 0) {
                    proxy.transfer(to, lastAmount, address(token));
                }
            }
            proxy.transfer(to, transferAmounts[i] + amountsToMint[i], address(token));
        }
    }

    function _toStateHolderKey(string memory a, string memory b) private pure returns(string memory) {
        return _toLowerCase(string(abi.encodePacked(a, ".", b)));
    }

    function _toString(address _addr) private pure returns(string memory) {
        bytes32 value = bytes32(uint256(_addr));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint i = 0; i < 20; i++) {
            str[2+i*2] = alphabet[uint(uint8(value[i + 12] >> 4))];
            str[3+i*2] = alphabet[uint(uint8(value[i + 12] & 0x0f))];
        }
        return string(str);
    }

    function _toLowerCase(string memory str) private pure returns(string memory) {
        bytes memory bStr = bytes(str);
        for (uint i = 0; i < bStr.length; i++) {
            bStr[i] = bStr[i] >= 0x41 && bStr[i] <= 0x5A ? bytes1(uint8(bStr[i]) + 0x20) : bStr[i];
        }
        return string(bStr);
    }
}

interface IMVDProxy {
    function getStateHolderAddress() external view returns(address);
    function getMVDWalletAddress() external view returns(address);
    function transfer(address receiver, uint256 value, address token) external;
    function flushToWallet(address tokenAddress, bool is721, uint256 tokenId) external;
}

interface IStateHolder {
    function setUint256(string calldata name, uint256 value) external returns(uint256);
    function getUint256(string calldata name) external view returns(uint256);
    function getAddress(string calldata name) external view returns(address);
    function setAddress(string calldata varName, address val) external returns (address);
    function getBool(string calldata varName) external view returns (bool);
    function setBool(string calldata varName, bool val) external returns(bool);
    function clear(string calldata varName) external returns(string memory oldDataType, bytes memory oldVal);
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function safeApprove(address spender, uint256 amount) external;
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
    function mint(uint256 amount) external;
    function burn(uint256 amount) external;
}