//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "@ethereansos/swissknife/contracts/environment/optimism/OptimismLib.sol";
import { FixedInflation as Original } from "../../../fixed-inflation/FixedInflation.sol";

contract FixedInflation is Original {
    function _blockNumber() internal view override returns(uint256) {
        return OptimismLib._blockNumber();
    }
}