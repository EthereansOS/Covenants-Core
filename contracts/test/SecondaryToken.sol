pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SecondaryToken is ERC20 {
    constructor(address firstAccount, address secondaryAccount) ERC20("SecondaryToken", "SECT") {
        _mint(msg.sender, 1000000 * (10 ** uint256(decimals())));
        _mint(firstAccount, 1000000 * (10 ** uint256(decimals())));
        _mint(secondaryAccount, 1000000 * (10 ** uint256(decimals())));
    }
}