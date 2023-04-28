//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "@ethereansos/swissknife/contracts/environment/optimism/OptimismLib.sol";
import { FarmMainRegularMinStake as Original } from "../../../farming/FarmMainRegularMinStake.sol";

contract FarmMainRegularMinStake is Original {
    function _blockNumber() internal view override returns(uint256) {
        return OptimismLib._blockNumber();
    }
}