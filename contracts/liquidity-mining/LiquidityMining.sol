//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./ILiquidityMiningFactory.sol";
import "./LiquidityMiningData.sol";
import "./ILiquidityMiningExtension.sol";
import "../amm-aggregator/common/IAMM.sol";
import "./util/IERC20.sol";
import "./util/IERC20Mintable.sol";
import "./util/IEthItemOrchestrator.sol";
import "./util/INativeV1.sol";
import "./ILiquidityMining.sol";

contract LiquidityMining is ILiquidityMining {

    uint256 public constant ONE_HUNDRED = 10000;

    // event that tracks liquidity mining contracts deployed
    event RewardToken(address indexed rewardTokenAddress);
    // new liquidity mining position event
    event Transfer(uint256 indexed positionId, address indexed from, address indexed to);

    // factory address that will create clones of this contract
    address public _factory;
    // address of the extension of this contract
    address public _extension;
    // address of the reward token
    address public override _rewardTokenAddress;
    // liquidityMiningPosition token collection
    address public _positionTokenCollection;
    // array containing all the currently available liquidity mining setups
    LiquidityMiningSetup[] private _setups;
    // mapping containing all the positions
    mapping(uint256 => LiquidityMiningPosition) public _positions;
    // mapping containing the reward per token per setup per block
    mapping(uint256 => mapping(uint256 => uint256)) public _rewardPerTokenPerSetupPerBlock;
    // mapping containing all the blocks where an update has been triggered
    mapping(uint256 => uint256[]) public _setupUpdateBlocks;
    // mapping containing whether a liquidity mining position has been redeemed or not
    mapping(uint256 => bool) public _positionRedeemed;
    // mapping containing whether a liquidity mining position has been partially reedemed or not
    mapping(uint256 => uint256) public _partiallyRedeemed;
    // mapping containing whether a locked setup has ended or not and has been used for the rebalance
    mapping(uint256 => bool) public _finishedLockedSetups;
    // pinned setup index
    bool public _hasPinned;
    uint256 public _pinnedSetupIndex;

    /** Modifiers. */

    /** @dev byExtension modifier used to check for unauthorized changes. */
    modifier byExtension() {
        require(msg.sender == _extension, "Unauthorized");
        _;
    }

    /** @dev byPositionOwner modifier used to check for unauthorized accesses. */
    modifier byPositionOwner(uint256 positionId) {
        if(_positions[positionId].uniqueOwner != msg.sender) {
            try INativeV1(_positionTokenCollection).balanceOf(msg.sender, positionId) returns (uint256 balanceOf) {
                require(balanceOf == 1, "Not owned");
            } catch {
                revert("Not owned");
            }
        }
        _;
    }

    /** Public extension methods. */

    /** @dev function called by the factory contract to initialize a new clone.
      * @param extension liquidity mining contract extension (a wallet or an extension).
      * @param ownerInitData encoded call function of the extension (used from an extension).
      * @param orchestrator ethItemOrchestrator address.
      * @param name ethItem liquidity mining position token name.
      * @param symbol ethitem liquidity mining position token symbol.
      * @param collectionUri ethItem liquidity mining position token uri.
      * @param rewardTokenAddress the address of the reward token.
     */
    function initialize(address extension, bytes memory ownerInitData, address orchestrator, string memory name, string memory symbol, string memory collectionUri, address rewardTokenAddress) public {
        require(
            _factory == address(0),
            "Already initialized"
        );
        _factory = msg.sender;
        _extension = extension;
        _rewardTokenAddress = rewardTokenAddress;
        (_positionTokenCollection,) = IEthItemOrchestrator(orchestrator).createNative(abi.encodeWithSignature("init(string,string,bool,string,address,bytes)", name, symbol, false, collectionUri, address(this), ""), "");
        if (keccak256(ownerInitData) != keccak256("")) {
            (bool result,) = _extension.call(ownerInitData);
            require(result, "Error while initializing extension");
        }
        emit RewardToken(_rewardTokenAddress);
    }

    /** @dev allows this contract to receive eth. */
    receive() external payable {
    }

    /** @dev returns the liquidity mining setups.
      * @return array containing all the liquidity mining setups.
     */
    function setups() public view returns (LiquidityMiningSetup[] memory) {
        return _setups;
    }

    /** @dev returns the liquidity mining position associated with the input id.
      * @param id liquidity mining position id.
      * @return liquidity mining position stored at the given id.
     */
    function position(uint256 id) public view returns(LiquidityMiningPosition memory) {
        return _positions[id];
    }

    /** @dev returns the reward per token for the setup index at the given block number.
      * @param setupIndex index of the setup.
      * @param blockNumber block that wants to be inspected.
      * @return reward per token.
     */
    function rewardPerToken(uint256 setupIndex, uint256 blockNumber) public view returns(uint256) {
        return _rewardPerTokenPerSetupPerBlock[setupIndex][blockNumber];
    }

    /** @dev allows the extension to set the liquidity mining setups.
      * @param liquidityMiningSetups liquidity mining setups to set.
      * @param setPinned if we're updating the pinned setup or not.
      * @param pinnedIndex new pinned setup index.
      */
    function setLiquidityMiningSetups(LiquidityMiningSetupConfiguration[] memory liquidityMiningSetups, bool clearPinned, bool setPinned, uint256 pinnedIndex) public override byExtension {
        for (uint256 i = 0; i < liquidityMiningSetups.length; i++) {
            LiquidityMiningSetupConfiguration memory configuration = liquidityMiningSetups[i];
            LiquidityMiningSetup memory liquidityMiningSetup = configuration.add ? configuration.data : _setups[configuration.index];
            require(
                configuration.data.ammPlugin != address(0) &&
                (
                    (configuration.data.free && configuration.data.liquidityPoolTokenAddresses.length == 1) ||
                    (!configuration.data.free && configuration.data.liquidityPoolTokenAddresses.length > 0 && configuration.data.startBlock < configuration.data.endBlock)
                ),
                "Invalid setup configuration"
            );
            require(!configuration.add || liquidityMiningSetup.ammPlugin != address(0), "Invalid setup index");
            if(!configuration.add) {
                liquidityMiningSetup.liquidityPoolTokenAddresses = configuration.data.liquidityPoolTokenAddresses;
            }
            address mainTokenAddress = configuration.add ? configuration.data.mainTokenAddress : liquidityMiningSetup.mainTokenAddress;
            address ammPlugin = configuration.add ? configuration.data.ammPlugin : liquidityMiningSetup.ammPlugin;
            for(uint256 j = 0; j < configuration.data.liquidityPoolTokenAddresses.length; j++) {
                (,,address[] memory tokenAddresses) = IAMM(ammPlugin).byLiquidityPool(configuration.data.liquidityPoolTokenAddresses[j]);
                bool found = false;
                for(uint256 z = 0; z < tokenAddresses.length; z++) {
                    if(tokenAddresses[z] == mainTokenAddress) {
                        found = true;
                        break;
                    }
                }
                require(found, "No main token");
            }
            if (configuration.add) {
                configuration.data.totalSupply = 0;
                configuration.data.currentRewardPerBlock = configuration.data.free ? configuration.data.rewardPerBlock : 0;
                // adding new liquidity mining setup
                _setups.push(configuration.data);
            } else {
                if (liquidityMiningSetup.free) {
                    // update free liquidity mining setup reward per block
                    if (configuration.data.rewardPerBlock - liquidityMiningSetup.rewardPerBlock < 0) {
                        _rebalanceRewardPerBlock(configuration.index, liquidityMiningSetup.rewardPerBlock - configuration.data.rewardPerBlock, false);
                    } else {
                        _rebalanceRewardPerBlock(configuration.index, configuration.data.rewardPerBlock - liquidityMiningSetup.rewardPerBlock, true);
                    }
                    liquidityMiningSetup.rewardPerBlock = _setups[configuration.index].rewardPerBlock;
                    liquidityMiningSetup.currentRewardPerBlock = liquidityMiningSetup.rewardPerBlock;
                } else {
                    // update locked liquidity mining setup
                    liquidityMiningSetup.rewardPerBlock = configuration.data.rewardPerBlock;
                    liquidityMiningSetup.renewTimes = configuration.data.renewTimes;
                    liquidityMiningSetup.penaltyFee = configuration.data.penaltyFee;
                }
                _setups[configuration.index] = liquidityMiningSetup;
            }
        }
        // if we're clearing the pinned setup we must also remove the excess reward per block
        if (clearPinned) {
            _hasPinned = false;
            _rebalanceRewardPerToken(_pinnedSetupIndex, 0, false);
            _setups[_pinnedSetupIndex].rewardPerBlock = _setups[_pinnedSetupIndex].currentRewardPerBlock;
        }
        // check if we're updating the pinned setup
        if (!clearPinned && setPinned) {
            require(_setups[_pinnedSetupIndex].free, "Invalid pinned free setup");
            uint256 oldBalancedRewardPerBlock;
            // check if we already have a free pinned setup
            if (_hasPinned && _setups[_pinnedSetupIndex].free) {
                // calculate the old balanced reward by subtracting from the current pinned reward per block the starting reward per block (aka currentRewardPerBlock)
                oldBalancedRewardPerBlock = _setups[_pinnedSetupIndex].rewardPerBlock - _setups[_pinnedSetupIndex].currentRewardPerBlock;
                // remove it from the current pinned setup
                _rebalanceRewardPerBlock(_pinnedSetupIndex, oldBalancedRewardPerBlock, false);
            }
            oldBalancedRewardPerBlock = 0;
            for(uint256 i = 0; i < _setups.length; i++) {
                if(_setups[i].free || _setups[i].rewardPerBlock == 0 || block.number < _setups[i].startBlock || block.number > _setups[i].endBlock) {
                    continue;
                }
                oldBalancedRewardPerBlock += _setups[i].rewardPerBlock - _setups[i].currentRewardPerBlock;
            }
            // update pinned setup index
            _hasPinned = true;
            _pinnedSetupIndex = pinnedIndex;
            // update reward per token of new pinned setup by adding the old balanced reward per block, if there's some.
            if (_hasPinned && _setups[_pinnedSetupIndex].free) {
                _rebalanceRewardPerBlock(_pinnedSetupIndex, oldBalancedRewardPerBlock, true);
            }
        }
    }

    /** Public methods. */

    /** @dev function called by external users to open a new liquidity mining position.
      * @param request Liquidity Mining input data.
    */
    function openPosition(LiquidityMiningPositionRequest memory request) public payable returns(uint256 positionId) {
        require(request.setupIndex < _setups.length, "Invalid setup index");
        // retrieve the setup
        LiquidityMiningSetup storage chosenSetup = _setups[request.setupIndex];
        require(chosenSetup.free || (block.number >= chosenSetup.startBlock && block.number <= chosenSetup.endBlock), "Setup not available");
        (IAMM amm, uint256 liquidityPoolAmount, uint256 mainTokenAmount, bool involvingETH) = _transferToMeAndCheckAllowance(chosenSetup, chosenSetup.liquidityPoolTokenAddresses[request.liquidityPoolAddressIndex], request);
        // retrieve the unique owner
        address uniqueOwner = (request.positionOwner != address(0)) ? request.positionOwner : msg.sender;

        LiquidityPoolData memory liquidityPoolData = LiquidityPoolData(
            chosenSetup.liquidityPoolTokenAddresses[request.liquidityPoolAddressIndex],
            request.amountIsLiquidityPool ? liquidityPoolAmount : mainTokenAmount,
            chosenSetup.mainTokenAddress,
            request.amountIsLiquidityPool,
            involvingETH,
            address(this)
        );

        if (!liquidityPoolData.amountIsLiquidityPool) {
            // retrieve the poolTokenAmount from the amm
            if(liquidityPoolData.involvingETH) {
                (liquidityPoolData.amount,,) = amm.addLiquidity{value : msg.value}(liquidityPoolData);
            } else {
                (liquidityPoolData.amount,,) = amm.addLiquidity(liquidityPoolData);
            }
            liquidityPoolData.amountIsLiquidityPool = true;
        }
        // create the position id
        positionId = request.mintPositionToken ? _mintPosition(uniqueOwner) : uint256(keccak256(abi.encode(uniqueOwner, request.setupIndex, block.number)));
        // calculate the reward
        uint256 reward;
        uint256 lockedRewardPerBlock;
        if (!chosenSetup.free) {
            (reward, lockedRewardPerBlock) = _calculateLockedLiquidityMiningSetupReward(chosenSetup, mainTokenAmount);
            require(reward > 0 && lockedRewardPerBlock > 0, "Insufficient staked amount");
            ILiquidityMiningExtension(_extension).transferTo(reward, address(this));
            chosenSetup.currentRewardPerBlock += lockedRewardPerBlock;
        }
        _positions[positionId] = LiquidityMiningPosition({
            uniqueOwner: request.mintPositionToken ? address(0) : uniqueOwner,
            setupIndex : request.setupIndex,
            setupStartBlock : chosenSetup.startBlock,
            setupEndBlock : chosenSetup.endBlock,
            free : chosenSetup.free,
            liquidityPoolData: liquidityPoolData,
            reward: reward,
            lockedRewardPerBlock: lockedRewardPerBlock,
            creationBlock: block.number
        });
        if (chosenSetup.free) {
            _rebalanceRewardPerToken(request.setupIndex, liquidityPoolData.amount, false);
        } else {
            if (_hasPinned && _setups[_pinnedSetupIndex].free) {
                _rebalanceRewardPerBlock(_pinnedSetupIndex, lockedRewardPerBlock, false);
            }
        }

        emit Transfer(positionId, address(0), uniqueOwner);
    }

    /** @dev adds liquidity to the liquidity mining position at the given positionId using the given lpData.
      * @param positionId id of the liquidity mining position.
      * @param request update position request.
      */
    function addLiquidity(uint256 positionId, LiquidityMiningPositionRequest memory request) public payable byPositionOwner(positionId) {
        // retrieve liquidity mining position
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionId];
        // check if liquidity mining position is valid
        require(liquidityMiningPosition.free || liquidityMiningPosition.setupEndBlock >= block.number, "Invalid add liquidity");
        LiquidityMiningSetup memory chosenSetup = _setups[liquidityMiningPosition.setupIndex];
        (IAMM amm, uint256 liquidityPoolAmount, uint256 mainTokenAmount, bool involvingETH) = _transferToMeAndCheckAllowance(chosenSetup, liquidityMiningPosition.liquidityPoolData.liquidityPoolAddress, request);

        LiquidityPoolData memory liquidityPoolData = LiquidityPoolData(
            chosenSetup.liquidityPoolTokenAddresses[request.liquidityPoolAddressIndex],
            request.amountIsLiquidityPool ? liquidityPoolAmount : mainTokenAmount,
            chosenSetup.mainTokenAddress,
            request.amountIsLiquidityPool,
            involvingETH,
            address(this)
        );

        if (!liquidityPoolData.amountIsLiquidityPool) {
            // retrieve the poolTokenAmount from the amm
            if(liquidityPoolData.involvingETH) {
                (liquidityPoolData.amount,,) = amm.addLiquidity{value : msg.value}(liquidityPoolData);
            } else {
                (liquidityPoolData.amount,,) = amm.addLiquidity(liquidityPoolData);
            }
            liquidityPoolData.amountIsLiquidityPool = true;
        }

        // update the liquidity pool token amount
        liquidityMiningPosition.liquidityPoolData.amount += liquidityPoolData.amount;

        (uint256 newReward, uint256 newLockedRewardPerBlock) = liquidityMiningPosition.free ? (_calculateFreeLiquidityMiningSetupReward(positionId), 0) : _calculateLockedLiquidityMiningSetupReward(_setups[liquidityMiningPosition.setupIndex], mainTokenAmount);
        require(newReward > 0, "Reward cannot be 0");
        if (!liquidityMiningPosition.free) {
            // transfer the reward in advance to this contract
            ILiquidityMiningExtension(_extension).transferTo(newReward, address(this));
            // update the position reward, locked reward per block and the liquidity pool token amount
            liquidityMiningPosition.reward += newReward;
            liquidityMiningPosition.lockedRewardPerBlock += newLockedRewardPerBlock;
            _setups[liquidityMiningPosition.setupIndex].currentRewardPerBlock += newLockedRewardPerBlock;
            // rebalance the pinned reward per block
            if (_hasPinned && _setups[_pinnedSetupIndex].free) {
                _rebalanceRewardPerBlock(_pinnedSetupIndex, newLockedRewardPerBlock, false);
            }
        } else {
            // transfer the reward
            ILiquidityMiningExtension(_extension).transferTo(newReward, msg.sender);
            // update the creation block to avoid blocks before the new add liquidity
            liquidityMiningPosition.creationBlock = block.number;
            // rebalance the reward per token
            _rebalanceRewardPerToken(liquidityMiningPosition.setupIndex, liquidityPoolData.amount, false);
        }
    }

    /** @dev this function allows a wallet to update the extension of the given liquidity mining position.
      * @param to address of the new extension.
      * @param positionId id of the liquidity mining position.
     */
    function transfer(address to, uint256 positionId) public byPositionOwner(positionId) {
        // retrieve liquidity mining position
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionId];
        require(
            liquidityMiningPosition.liquidityPoolData.liquidityPoolAddress != address(0) &&
            to != address(0) &&
            liquidityMiningPosition.uniqueOwner == msg.sender &&
            liquidityMiningPosition.setupStartBlock == _setups[liquidityMiningPosition.setupIndex].startBlock &&
            liquidityMiningPosition.setupEndBlock == _setups[liquidityMiningPosition.setupIndex].endBlock,
        "Invalid liquidity mining position");
        liquidityMiningPosition.uniqueOwner = to;
        emit Transfer(positionId, msg.sender, to);
    }

    /** @dev this function allows a user to withdraw a partial reward.
      * @param positionId liquidity mining position id.
     */
    function partialReward(uint256 positionId) public byPositionOwner(positionId) {
        // retrieve liquidity mining position
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionId];
        // check if wallet is withdrawing using a liquidity mining position token
        bool hasPositionItem = address(INativeV1(_positionTokenCollection).asInteroperable(positionId)) != address(0);
        // check if liquidity mining position is valid
        require(liquidityMiningPosition.free || liquidityMiningPosition.setupEndBlock >= block.number, "Invalid partial reward");
        require(liquidityMiningPosition.liquidityPoolData.liquidityPoolAddress != address(0), "Invalid liquidityMiningPosition");

        // update extension if has liquidity mining position item
        liquidityMiningPosition.uniqueOwner = hasPositionItem ? msg.sender : liquidityMiningPosition.uniqueOwner;
        if (!liquidityMiningPosition.free) {
            // check if reward is available
            require(liquidityMiningPosition.reward > 0, "No reward");
            // calculate the reward from the liquidity mining position creation block to the current block multiplied by the reward per block
            uint256 reward = (block.number >= liquidityMiningPosition.setupEndBlock) ? liquidityMiningPosition.reward : ((block.number - liquidityMiningPosition.creationBlock) * liquidityMiningPosition.lockedRewardPerBlock);
            require(reward <= liquidityMiningPosition.reward, "Reward is bigger than expected");
            // remove the partial reward from the liquidity mining position total reward
            liquidityMiningPosition.reward = liquidityMiningPosition.reward - reward;
            // withdraw the values using the helper
            _withdraw(positionId, false, reward, true);
        } else {
            // withdraw the values
            _withdraw(positionId, false, _calculateFreeLiquidityMiningSetupReward(positionId), true);
            // update the liquidity mining position creation block to exclude all the rewarded blocks
            liquidityMiningPosition.creationBlock = block.number;
        }
        // remove extension if has liquidity mining position item
        liquidityMiningPosition.uniqueOwner = hasPositionItem ? address(0) : liquidityMiningPosition.uniqueOwner;
    }

    /** @dev this function allows a extension to unlock its locked liquidity mining position receiving back its tokens or the lpt amount.
      * @param positionId liquidity mining position id.
      * @param unwrapPair if the caller wants to unwrap his pair from the liquidity pool token or not.
      */
    function unlock(uint256 positionId, bool unwrapPair) public payable byPositionOwner(positionId) {
        // retrieve liquidity mining position
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionId];
        // check if wallet is withdrawing using a liquidity mining position token
        bool hasPositionItem = address(INativeV1(_positionTokenCollection).asInteroperable(positionId)) != address(0);
        // check if liquidity mining position is valid
        require(hasPositionItem || liquidityMiningPosition.uniqueOwner == msg.sender, "Invalid caller");
        require(liquidityMiningPosition.liquidityPoolData.liquidityPoolAddress != address(0), "Invalid liquidityMiningPosition");
        require(!liquidityMiningPosition.free && liquidityMiningPosition.setupEndBlock >= block.number, "Invalid unlock");
        require(!_positionRedeemed[positionId], "LiquidityMiningPosition already redeemed");
        // must pay a penalty fee
        uint256 amount = _partiallyRedeemed[positionId];
        amount += (liquidityMiningPosition.reward * ((_setups[liquidityMiningPosition.setupIndex].penaltyFee * 1e18) / ONE_HUNDRED) / 1e18);
        if(_rewardTokenAddress != address(0)) {
            _safeTransferFrom(_rewardTokenAddress, msg.sender, address(this), amount);
            _safeApprove(_rewardTokenAddress, _extension, amount);
            ILiquidityMiningExtension(_extension).backToYou(amount);
        } else {
            require(msg.value == amount, "Invalid sent amount");
            ILiquidityMiningExtension(_extension).backToYou{value : amount}(amount);
        }
        if (hasPositionItem) {
            _burnPosition(positionId, msg.sender);
        }
        _exit(positionId, unwrapPair);
    }

    /** @dev this function allows a extension to withdraw its liquidity mining position using its liquidity mining position token or not.
      * @param positionId liquidity mining position id.
      * @param unwrapPair if the caller wants to unwrap his pair from the liquidity pool token or not.
      */
    function withdraw(uint256 positionId, bool unwrapPair) public byPositionOwner(positionId) {
        // retrieve liquidity mining position
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionId];
        // check if wallet is withdrawing using a liquidity mining position token
        bool hasPositionItem = address(INativeV1(_positionTokenCollection).asInteroperable(positionId)) != address(0);
        // check if liquidity mining position is valid
        require(liquidityMiningPosition.liquidityPoolData.liquidityPoolAddress != address(0), "Invalid liquidityMiningPosition");
        require(liquidityMiningPosition.free || liquidityMiningPosition.setupEndBlock <= block.number, "Invalid withdraw");
        require(!_positionRedeemed[positionId], "LiquidityMiningPosition already redeemed");
        if(hasPositionItem) {
            _burnPosition(positionId, msg.sender);
        }
        _withdraw(positionId, unwrapPair, liquidityMiningPosition.reward, false);
        _positionRedeemed[positionId] = true;
    }

    /** @dev this function allows any user to rebalance the pinned setup. */
    function rebalancePinnedSetup() public {
        if (!_hasPinned || !_setups[_pinnedSetupIndex].free) return;
        uint256 amount;
        for (uint256 i = 0; i < _setups.length; i++) {
            if (_setups[i].free) continue;
            // this is a locked setup that it's currently active or it's a new one
            if (block.number >= _setups[i].startBlock && block.number < _setups[i].endBlock) {
                // the amount to add to the pinned is given by the difference between the reward per block and currently locked one
                // in the case of a new setup, the currentRewardPerBlock is 0 so the difference is the whole rewardPerBlock
                amount += (_setups[i].rewardPerBlock - _setups[i].currentRewardPerBlock);
            // this is a locked setup that has expired
            } else if (block.number >= _setups[i].endBlock) {
                // check if the setup is renewable
                if (_setups[i].renewTimes > 0) {
                    _setups[i].renewTimes -= 1;
                    // if it is, we renew it and add the reward per block
                    _renewSetup(i);
                    amount += _setups[i].rewardPerBlock;
                } else {
                    _finishedLockedSetups[i] = true;
                }
            }
        }
        _setups[_pinnedSetupIndex].rewardPerBlock = _setups[_pinnedSetupIndex].currentRewardPerBlock;
        if (_hasPinned && _setups[_pinnedSetupIndex].free) {
            _rebalanceRewardPerBlock(_pinnedSetupIndex, amount, true);
        }
    }

    /** Private methods. */

    /** @dev function used to calculate the reward in a locked liquidity mining setup.
      * @param setup liquidity mining setup.
      * @param mainTokenAmount amount of main token.
      * @return reward total reward for the liquidity mining position extension.
      * @return relativeRewardPerBlock returned for the pinned free setup balancing.
     */
    function _calculateLockedLiquidityMiningSetupReward(LiquidityMiningSetup storage setup, uint256 mainTokenAmount) private view returns(uint256 reward, uint256 relativeRewardPerBlock) {
        uint256 remainingBlocks = block.number > setup.endBlock ? 0 : setup.endBlock - block.number;
        // get amount of remaining blocks
        require(remainingBlocks > 0, "Setup ended");
        // get total reward still available (= 0 if rewardPerBlock = 0)
        require(setup.rewardPerBlock * remainingBlocks > 0, "No rewards");
        // calculate relativeRewardPerBlock
        relativeRewardPerBlock = (setup.rewardPerBlock * ((mainTokenAmount * 1e18) / (setup.rewardPerBlock * (setup.endBlock - setup.startBlock)))) / 1e18;
        // check if rewardPerBlock is greater than 0
        require(relativeRewardPerBlock > 0, "relativeRewardPerBlock must be greater than 0");
        // calculate reward by multiplying relative reward per block and the remaining blocks
        reward = relativeRewardPerBlock * remainingBlocks;
        // check if the reward is still available
        require(reward <= setup.rewardPerBlock * remainingBlocks, "No availability");
    }

    /** @dev function used to calculate the reward in a free liquidity mining setup.
      * @param positionId wallet liquidity mining position id.
      * @return reward total reward for the liquidity mining position extension.
     */
    function _calculateFreeLiquidityMiningSetupReward(uint256 positionId) public view returns(uint256 reward) {
        LiquidityMiningPosition memory liquidityMiningPosition = _positions[positionId];
        for (uint256 i = 0; i < _setupUpdateBlocks[liquidityMiningPosition.setupIndex].length; i++) {
            if (liquidityMiningPosition.creationBlock < _setupUpdateBlocks[liquidityMiningPosition.setupIndex][i]) {
                reward += (_rewardPerTokenPerSetupPerBlock[liquidityMiningPosition.setupIndex][_setupUpdateBlocks[liquidityMiningPosition.setupIndex][i]] / 1e18) * liquidityMiningPosition.liquidityPoolData.amount;
            }
        }
        require(reward > 0, "No reward");
    }

    /** @dev returns true if the input token is in the tokens array, hence is an accepted one; false otherwise.
      * @param tokens array of tokens addresses.
      * @param token token address to check.
      * @return true if token in tokens, false otherwise.
      */
    function _isAcceptedToken(address[] memory tokens, address token) private pure returns(bool) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    /** @dev this function performs the transfer of the tokens that will be staked, interacting with the AMM plugin.
      * @param setup the chosen setup.
      * @param liquidityPoolAddress the liquidity pool address.
      * @param request new open position request.
      * @return amm AMM plugin interface.
      * @return liquidityPoolAmount amount of liquidity pool token.
      * @return mainTokenAmount amount of main token staked.
      * @return involvingETH if the inputed flag is consistent.
     */
    function _transferToMeAndCheckAllowance(
        LiquidityMiningSetup memory setup,
        address liquidityPoolAddress,
        LiquidityMiningPositionRequest memory request
    ) private returns(
        IAMM amm,
        uint256 liquidityPoolAmount,
        uint256 mainTokenAmount,
        bool involvingETH
    ) {
        require(request.amount > 0, "No amount");
        // retrieve the values
        amm = IAMM(setup.ammPlugin);
        liquidityPoolAmount = request.amountIsLiquidityPool ? request.amount : 0;
        mainTokenAmount = request.amountIsLiquidityPool ? 0 : request.amount;
        address[] memory tokens;
        uint256[] memory tokenAmounts;
        // if liquidity pool token amount is provided, the position is opened by liquidity pool token amount
        if(request.amountIsLiquidityPool) {
            _safeTransferFrom(liquidityPoolAddress, msg.sender, address(this), liquidityPoolAmount);
            (tokenAmounts, tokens) = amm.byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount);
        } else {
            // else it is opened by the tokens amounts
            (liquidityPoolAmount, tokenAmounts, tokens) = amm.byTokenAmount(liquidityPoolAddress, setup.mainTokenAddress, mainTokenAmount);
        }

        // check if the eth is involved in the request
        address ethAddress = address(0); 
        if(request.involvingETH) {
            (ethAddress,,) = amm.data();
        }
        // iterate the tokens and perform the transferFrom and the approve
        for(uint256 i = 0; i < tokens.length; i++) {
            if(tokens[i] == setup.mainTokenAddress) {
                mainTokenAmount = tokenAmounts[i];
                if(request.amountIsLiquidityPool) {
                    break;
                }
            }
            if(request.amountIsLiquidityPool) {
                continue;
            }
            if(request.involvingETH && ethAddress == tokens[i]) {
                involvingETH = true;
                require(msg.value == tokenAmounts[i], "Incorrect eth value");
            } else {
                _safeTransferFrom(tokens[i], msg.sender, address(this), tokenAmounts[i]);
                _safeApprove(tokens[i], setup.ammPlugin, tokenAmounts[i]);
            }
        }
    }

    /** @dev mints a new PositionToken inside the collection for the given wallet.
      * @param uniqueOwner liquidityMiningPosition token extension.
      * @return objectId new liquidityMiningPosition token object id.
     */
    function _mintPosition(address uniqueOwner) private returns(uint256 objectId) {
        // TODO: metadata
        (objectId,) = INativeV1(_positionTokenCollection).mint(1, "UNIFI PositionToken", "UPT", "google.com", false);
        INativeV1(_positionTokenCollection).safeTransferFrom(address(this), uniqueOwner, objectId, 1, "");
    }

    /** @dev burns a PositionToken from the collection.
      * @param positionId wallet liquidity mining position id.
      * @param uniqueOwner staking liquidity mining position extension address.
      */
    function _burnPosition(uint256 positionId, address uniqueOwner) private {
        INativeV1 positionCollection = INativeV1(_positionTokenCollection);
        // transfer the liquidity mining position token to this contract
        positionCollection.asInteroperable(positionId).transferFrom(uniqueOwner, address(this), positionCollection.toInteroperableInterfaceAmount(positionId, 1));
        // burn the liquidity mining position token
        positionCollection.burn(positionId, 1);
        // withdraw the liquidityMiningPosition
        _positions[positionId].uniqueOwner = uniqueOwner;
    }

    /** @dev helper function that performs the exit of the given liquidity mining position for the given setup index and unwraps the pair if the extension has chosen to do so.
      * @param positionId id of the liquidity mining position.
      * @param unwrapPair if the extension wants to unwrap the pair or not.
     */
    function _exit(uint256 positionId, bool unwrapPair) private {
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionId];
        (uint256 exitFeePercentage, address exitFeeWallet) = ILiquidityMiningFactory(_factory).feePercentageInfo();
        // pay the fees!
        if (exitFeePercentage > 0) {
            uint256 fee = (liquidityMiningPosition.liquidityPoolData.amount * ((exitFeePercentage * 1e18) / ONE_HUNDRED)) / 1e18;
            _safeTransfer(liquidityMiningPosition.liquidityPoolData.liquidityPoolAddress, exitFeeWallet, fee);
            liquidityMiningPosition.liquidityPoolData.amount = liquidityMiningPosition.liquidityPoolData.amount - fee;
        }
        // check if the user wants to unwrap its pair or not
        if (unwrapPair) {
            // remove liquidity using AMM
            address ammPlugin = _setups[liquidityMiningPosition.setupIndex].ammPlugin;
            liquidityMiningPosition.liquidityPoolData.receiver = liquidityMiningPosition.uniqueOwner;
            _safeApprove(liquidityMiningPosition.liquidityPoolData.liquidityPoolAddress, ammPlugin, liquidityMiningPosition.liquidityPoolData.amount);
            (,uint256[] memory amounts,) = IAMM(ammPlugin).removeLiquidity(liquidityMiningPosition.liquidityPoolData);
            require(amounts[0] > 0 && amounts[1] > 0, "Insufficient amount");
        } else {
            // send back the liquidity pool token amount without the fee
            _safeTransfer(liquidityMiningPosition.liquidityPoolData.liquidityPoolAddress, liquidityMiningPosition.uniqueOwner, liquidityMiningPosition.liquidityPoolData.amount);
        }
        // rebalance the setup if not free
        if (!_setups[liquidityMiningPosition.setupIndex].free && !_finishedLockedSetups[liquidityMiningPosition.setupIndex]) {
            // check if the setup has been updated or not
            if (liquidityMiningPosition.setupEndBlock == _setups[liquidityMiningPosition.setupIndex].endBlock) {
                // check if it's finished (this is a withdraw) or not (a unlock)
                if (_setups[liquidityMiningPosition.setupIndex].endBlock <= block.number) {
                    // the locked setup must be considered finished only if it's not renewable
                    _finishedLockedSetups[liquidityMiningPosition.setupIndex] = _setups[liquidityMiningPosition.setupIndex].renewTimes == 0;
                    if (_hasPinned && _setups[_pinnedSetupIndex].free) {
                        _rebalanceRewardPerBlock(_pinnedSetupIndex, _setups[liquidityMiningPosition.setupIndex].rewardPerBlock - _setups[liquidityMiningPosition.setupIndex].currentRewardPerBlock, false);
                    }
                    if (_setups[liquidityMiningPosition.setupIndex].renewTimes > 0) {
                        _setups[liquidityMiningPosition.setupIndex].renewTimes -= 1;
                        // renew the setup if renewable
                        _renewSetup(liquidityMiningPosition.setupIndex);
                    }
                } else {
                    if (_hasPinned && _setups[_pinnedSetupIndex].free) {
                        _rebalanceRewardPerBlock(_pinnedSetupIndex, liquidityMiningPosition.lockedRewardPerBlock, true);
                    }
                }
            }
        }
        // delete the liquidity mining position after the withdraw
        _positions[positionId] = _positions[0x0];
    }

    /** @dev Renews the setup with the given index.
      * @param setupIndex index of the setup to renew.
     */
    function _renewSetup(uint256 setupIndex) private {
        uint256 duration = _setups[setupIndex].endBlock - _setups[setupIndex].startBlock;
        _setups[setupIndex].startBlock = block.number + 1;
        _setups[setupIndex].endBlock = block.number + 1 + duration;
        _setups[setupIndex].currentRewardPerBlock = 0;
    }

    /** @dev withdraw helper method.
      * @param positionId staking liquidity mining position id.
      * @param unwrapPair if the caller wants to unwrap his pair from the liquidity pool token or not.
      * @param reward amount to withdraw.
      * @param isPartial if it's a partial withdraw or not.
     */
    function _withdraw(uint256 positionId, bool unwrapPair, uint256 reward, bool isPartial) private {
        LiquidityMiningPosition memory liquidityMiningPosition = _positions[positionId];
        // rebalance setup, if free
        if (_setups[liquidityMiningPosition.setupIndex].free && !isPartial) {
            _rebalanceRewardPerToken(liquidityMiningPosition.setupIndex, liquidityMiningPosition.liquidityPoolData.amount, true);
            reward = (reward == 0) ? _calculateFreeLiquidityMiningSetupReward(positionId) : reward;
            require(reward > 0, "Reward cannot be 0");
        }
        // transfer the reward
        if (reward > 0) {
            if(!liquidityMiningPosition.free) {
                _rewardTokenAddress != address(0) ? _safeTransfer(_rewardTokenAddress, liquidityMiningPosition.uniqueOwner, reward) : payable(liquidityMiningPosition.uniqueOwner).transfer(reward);
            } else {
                ILiquidityMiningExtension(_extension).transferTo(reward, liquidityMiningPosition.uniqueOwner);
            }
        }
        if (!isPartial) {
            _exit(positionId, unwrapPair);
        } else {
            _partiallyRedeemed[positionId] = reward;
        }
    }

    /** @dev function used to rebalance the reward per block in the given free liquidity mining setup.
      * @param setupIndex setup to rebalance.
      * @param lockedRewardPerBlock new liquidity mining position locked reward per block that must be subtracted from the given free liquidity mining setup reward per block.
      * @param fromExit if the rebalance is caused by an exit from the locked liquidity mining position or not.
      */
    function _rebalanceRewardPerBlock(uint256 setupIndex, uint256 lockedRewardPerBlock, bool fromExit) private {
        LiquidityMiningSetup storage setup = _setups[setupIndex];
        _rebalanceRewardPerToken(setupIndex, 0, fromExit);
        fromExit ? setup.rewardPerBlock += lockedRewardPerBlock : setup.rewardPerBlock -= lockedRewardPerBlock;
    }

    /** @dev function used to rebalance the reward per token in a free liquidity mining setup.
      * @param setupIndex index of the setup to rebalance.
      * @param liquidityPoolTokenAmount amount of liquidity pool token being added.
      * @param fromExit if the rebalance is caused by an exit from the free liquidity mining position or not.
     */
    function _rebalanceRewardPerToken(uint256 setupIndex, uint256 liquidityPoolTokenAmount, bool fromExit) private {
        LiquidityMiningSetup storage setup = _setups[setupIndex];
        if(setup.lastBlockUpdate > 0 && setup.totalSupply > 0) {
            // add the block to the setup update blocks
            _setupUpdateBlocks[setupIndex].push(block.number);
            // update the reward token
            _rewardPerTokenPerSetupPerBlock[setupIndex][block.number] = (((block.number - setup.lastBlockUpdate) * setup.rewardPerBlock) * 1e18) / setup.totalSupply;
        }
        // update the last block update variable
        setup.lastBlockUpdate = block.number;
        // update total supply in the setup AFTER the reward calculation - to let previous liquidity mining position holders to calculate the correct value
        fromExit ? setup.totalSupply -= liquidityPoolTokenAmount : setup.totalSupply += liquidityPoolTokenAmount;
    }

    /** @dev function used to safely approve ERC20 transfers.
      * @param erc20TokenAddress address of the token to approve.
      * @param to receiver of the approval.
      * @param value amount to approve for.
     */
    function _safeApprove(address erc20TokenAddress, address to, uint256 value) internal virtual {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).approve.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'APPROVE_FAILED');
    }

    /** @dev function used to safe transfer ERC20 tokens.
      * @param erc20TokenAddress address of the token to transfer.
      * @param to receiver of the tokens.
      * @param value amount of tokens to transfer.
     */
    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) internal virtual {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }

    /** @dev this function safely transfers the given ERC20 value from an address to another.
      * @param erc20TokenAddress erc20 token address.
      * @param from address from.
      * @param to address to.
      * @param value amount to transfer.
     */
    function _safeTransferFrom(address erc20TokenAddress, address from, address to, uint256 value) private {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFERFROM_FAILED');
    }
}