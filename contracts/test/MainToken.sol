pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MainToken is ERC20 {
    constructor() ERC20("MainToken", "MAIN") {
        _mint(msg.sender, 1000000 * (10 ** uint256(decimals())));
        _mint(0xFa0858e245886840F4E439725D98AEF89F8EE634, 1000000 * (10 ** uint256(decimals())));
        _mint(0x60eB6B93B72cdE37c75c117306312Aa21973f204, 1000000 * (10 ** uint256(decimals())));
    }
}