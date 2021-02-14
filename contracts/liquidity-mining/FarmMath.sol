//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./IFarmMath.sol";
import "./ILiquidityMining.sol";

contract FarmMath is IFarmMath {

    /* OPERATIONS:
     * 0: Toggle Setup - Active and terminated setup
     * 1: Toggle Setup - Re-active new pinned setup
     * 2: Disable Setup
     * 3: Edit RewardPerBlock in free non-pinned setup
     * 4: Open new Position
     * 5: Add liquidity
     * 6: Withdraw position
     * 7: Unlock position
     */
    function calculateGiveAndTransfer(LiquidityMiningSetup memory setup, uint256 setupIndex, bool _hasPinned, uint256 _pinnedSetupIndex, uint256 operation, bytes memory data) public override view returns(LiquidityMiningSetup memory newSetup, uint256 toGive, uint256 toTransfer) {
        (newSetup, toGive, toTransfer) =
        operation == 0 ? _toggleActiveAndTerminatedSetup(setup, setupIndex, _hasPinned, _pinnedSetupIndex, data) :
        operation == 1 ? _toggleActivePinnedSetup(setup, setupIndex, _hasPinned, _pinnedSetupIndex, data) :
        operation == 2 ? _disableSetup(setup, setupIndex, _hasPinned, _pinnedSetupIndex, data) :
        operation == 3 ? _editFreeNonPinnedRewardPerBlock(setup, setupIndex, _hasPinned, _pinnedSetupIndex, data) :
        operation == 4 ? _clearPinned(setup, setupIndex, _hasPinned, _pinnedSetupIndex, data) :
        operation == 5 ? _setPinned(setup, setupIndex, _hasPinned, _pinnedSetupIndex, data) :
        _openPositionOrAddLiquidity(setup, setupIndex, _hasPinned, _pinnedSetupIndex, data);
    }

    //0
    function _toggleActiveAndTerminatedSetup(LiquidityMiningSetup memory setup, uint256 setupIndex, bool _hasPinned, uint256 _pinnedSetupIndex, bytes memory data) private view returns(LiquidityMiningSetup memory newSetup, uint256 toGive, uint256 toTransfer) {
        newSetup = setup;
        if(setup.active && block.number >= setup.endBlock) {
            if(setup.totalSupply == 0) {
                toGive = ((setup.endBlock - setup.startBlock) * setup.rewardPerBlock);
            }
            if(!setup.info.free && !_hasPinned && setup.totalSupply != 0) {
                uint256 availableToStake = setup.info.maxStakeable - setup.totalSupply;
                uint256 relativeRewardPerBlock = setup.rewardPerBlock * (((availableToStake * 1e18) / setup.info.maxStakeable) / 1e18);
                toGive = ((setup.endBlock - setup.startBlock) * relativeRewardPerBlock);
            }
            if(!setup.info.free && _hasPinned) {
                //Send to pinned the block end info
            }
            if(_hasPinned && setupIndex == _pinnedSetupIndex) {
                toGive = ((block.number - setup.endBlock) * (setup.rewardPerBlock - setup.info.originalRewardPerBlock));
            }
        }

        if(setup.info.renewTimes != 0) {
            toTransfer = setup.info.blockDuration * setup.rewardPerBlock;
        }
    }

    //1
    function _toggleActivePinnedSetup(LiquidityMiningSetup memory setup, uint256 setupIndex, bool _hasPinned, uint256 _pinnedSetupIndex, bytes memory data) private view returns(LiquidityMiningSetup memory newSetup, uint256 toGive, uint256 toTransfer) {
        if(_hasPinned && setupIndex == _pinnedSetupIndex && setup.totalSupply != 0) {
            toGive = ((block.number - setup.endBlock) * setup.rewardPerBlock - setup.info.originalRewardPerBlock);
        }
    }

    //2
    function _disableSetup(LiquidityMiningSetup memory setup, uint256, bool _hasPinned, uint256, bytes memory) private view returns(LiquidityMiningSetup memory newSetup, uint256 toGive, uint256 toTransfer) {
        if(setup.info.free) {
            if(setup.totalSupply == 0) {
                toGive = ((block.number - setup.startBlock) * setup.rewardPerBlock);
                if(setup.endBlock > block.number) {
                    toGive = ((setup.endBlock - block.number) * setup.rewardPerBlock);
                }
            } else {
                if(setup.endBlock > block.number) {
                    toGive = ((setup.endBlock - block.number) * setup.rewardPerBlock);
                }
            }
        } else {
            if(_hasPinned) {
                if(setup.endBlock > block.number) {
                    toGive = ((setup.endBlock - block.number) * setup.rewardPerBlock);
                }
            } else {
                if(setup.totalSupply == 0) {
                    toGive = ((block.number - setup.startBlock) * setup.rewardPerBlock);
                    if(setup.endBlock > block.number) {
                        toGive = ((setup.endBlock - block.number) * setup.rewardPerBlock);
                    }
                } else {
                    if(setup.startBlock < block.number) {
                        uint256 availableToStake = setup.info.maxStakeable - setup.totalSupply;
                        uint256 rewardToGiveBack = setup.rewardPerBlock * (((availableToStake * 1e18) / setup.info.maxStakeable) / 1e18);
                        toGive = ((block.number - setup.startBlock) * rewardToGiveBack);
                    }
                    if(setup.endBlock > block.number) {
                        toGive = ((setup.endBlock - block.number) * setup.rewardPerBlock);
                    }
                }
            }
        }
    }

    //3
    function _editFreeNonPinnedRewardPerBlock(LiquidityMiningSetup memory setup, uint256, bool, uint256, bytes memory data) private view returns(LiquidityMiningSetup memory newSetup, uint256 toGive, uint256 toTransfer) {
        uint256 newOriginalRewardPerBlock = abi.decode(data, (uint256));
        if(setup.totalSupply == 0) {
            toGive = ((block.number - setup.startBlock) * setup.rewardPerBlock);
            setup.startBlock = block.number;
        }
        uint256 difference = newOriginalRewardPerBlock < setup.info.originalRewardPerBlock ? setup.info.originalRewardPerBlock - newOriginalRewardPerBlock : newOriginalRewardPerBlock - setup.info.originalRewardPerBlock;
        uint256 duration = setup.endBlock - block.number;
        uint256 amount = difference * duration;
        if (amount > 0) {
            if (newOriginalRewardPerBlock < setup.info.originalRewardPerBlock) {
                toGive += amount;
            } else {
                toTransfer = amount;
            }
        }
        newSetup = setup;
    }

    //4
    function _clearPinned(LiquidityMiningSetup memory setup, uint256, bool, uint256, bytes memory) private view returns(LiquidityMiningSetup memory newSetup, uint256 toGive, uint256 toTransfer) {
        if (setup.totalSupply == 0) {
            if(setup.endBlock > block.number) {
                toGive = (block.number - setup.startBlock) * setup.rewardPerBlock;
            } else {
                toGive = (setup.endBlock - setup.startBlock) * setup.rewardPerBlock;
                toGive += (block.number - setup.endBlock) * (setup.rewardPerBlock - setup.info.originalRewardPerBlock);
            }
        }
    }

    //5
    function _setPinned(LiquidityMiningSetup memory setup, uint256, bool _hasPinned, uint256 _pinnedSetupIndex, bytes memory) private view returns(LiquidityMiningSetup memory newSetup, uint256 toGive, uint256 toTransfer) {
        if(setup.totalSupply == 0) {
            toGive += (block.number - setup.startBlock) * setup.rewardPerBlock;
        }
        LiquidityMiningSetup[] memory _setups = ILiquidityMining(msg.sender).setups();
        for (uint256 i = 0; i < _setups.length; i++) {
            LiquidityMiningSetup memory lockedSetup = _setups[i];
            if(lockedSetup.info.free || !lockedSetup.active) continue;
            if(lockedSetup.endBlock < block.number) {
                if(lockedSetup.totalSupply == 0) {
                    toGive += (lockedSetup.endBlock - lockedSetup.startBlock) * lockedSetup.rewardPerBlock;
                } else {
                    uint256 availableToStake = lockedSetup.info.maxStakeable - lockedSetup.totalSupply;
                    uint256 relativeRewardPerBlock = lockedSetup.rewardPerBlock * (((availableToStake * 1e18) / lockedSetup.info.maxStakeable) / 1e18);
                    toGive += ((lockedSetup.endBlock - lockedSetup.startBlock) * relativeRewardPerBlock);
                }
            } else {
                if(lockedSetup.totalSupply == 0) {
                    toGive += (block.number - lockedSetup.startBlock) * lockedSetup.rewardPerBlock;
                } else {
                    uint256 availableToStake = lockedSetup.info.maxStakeable - lockedSetup.totalSupply;
                    uint256 relativeRewardPerBlock = lockedSetup.rewardPerBlock * (((availableToStake * 1e18) / lockedSetup.info.maxStakeable) / 1e18);
                    toGive += ((block.number - lockedSetup.startBlock) * relativeRewardPerBlock);
                }
            }
        }
    }

    //6
    function _openPositionOrAddLiquidity(LiquidityMiningSetup memory setup, uint256 setupIndex, bool _hasPinned, uint256 _pinnedIndex, bytes memory) private view returns(LiquidityMiningSetup memory newSetup, uint256 toGive, uint256 toTransfer) {
        if(setup.totalSupply == 0) {
            toGive = ((block.number - setup.startBlock) * setup.rewardPerBlock);
        } else if(!setup.info.free) {
            uint256 availableToStake = setup.info.maxStakeable - setup.totalSupply;
            uint256 relativeRewardPerBlock = setup.rewardPerBlock * (((availableToStake * 1e18) / setup.info.maxStakeable) / 1e18);
            toGive = ((block.number - setup.startBlock) * relativeRewardPerBlock);
        }
    }
}