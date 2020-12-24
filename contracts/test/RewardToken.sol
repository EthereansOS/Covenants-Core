pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RewardToken is ERC20 {
    constructor() ERC20("RewardToken", "RWRD") {
        _mint(msg.sender, 10000000 * (10 ** uint256(decimals())));
    }

    function mint(address wallet, uint256 amount) public returns (bool) {
        _mint(wallet, amount);
        return true;
    }
}