//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../amm-aggregator/common/IAMM.sol";
import "./ILiquidityMining.sol";
import "./ILiquidityMiningExtension.sol";
import "./ILiquidityMiningFactory.sol";
import "./util/IERC20.sol";
import "./util/IEthItemOrchestrator.sol";
import "./util/INativeV1.sol";
import "./util/ERC1155Receiver.sol";

contract LiquidityMining is ILiquidityMining, ERC1155Receiver {

    // max number of contemporary locked
    uint256 public override constant MAX_CONTEMPORARY_LOCKED = 4;
    // percentage
    uint256 public override constant ONE_HUNDRED = 1e18;
    // event that tracks liquidity mining contracts deployed
    event RewardToken(address indexed rewardTokenAddress);
    // new liquidity mining position event
    event Transfer(uint256 indexed positionId, address indexed from, address indexed to);
    // event that tracks involved tokens for this contract
    event SetupToken(address indexed mainToken, address indexed involvedToken);
    // event that tracks farm tokens
    event FarmToken(uint256 indexed objectId, address indexed liquidityPoolToken, uint256 setupIndex, uint256 endBlock);

    // factory address that will create clones of this contract
    address public _factory;
    // address of the extension of this contract
    address public _extension;
    // address of the reward token
    address public override _rewardTokenAddress;
     // liquidity farm token collection
    address public _liquidityFarmTokenCollection;
    // array containing all the currently available liquidity mining setups
    LiquidityMiningSetup[] public _setups;
    // mapping containing all the positions
    mapping(uint256 => LiquidityMiningPosition) public _positions;
    // mapping containing the reward per token per setup per block
    mapping(uint256 => uint256) private _rewardPerTokenPerSetup;
    // mapping containing the reward per token paid per position
    mapping(uint256 => uint256) private _rewardPerTokenPaid;
    // mapping containing whether a liquidity mining position has been partially reedemed or not
    mapping(uint256 => uint256) private _partiallyRedeemed;
    // mapping containing object id to setup index
    mapping(uint256 => uint256) public _objectIdSetup;
    // number of positions currently opened in the contract
    uint256 private _positionsCount;
    // amount of reward received from the extension
    uint256 private _rewardReceived;
    // amount of reward paid by the contract
    uint256 private _rewardPaid;
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
        require(_positions[positionId].uniqueOwner == msg.sender && _positions[positionId].creationBlock != 0, "Not owned");
        _;
    }

    /** @dev activeExtensionOnly modifier used to check for function calls only if the extension is active. */
    modifier activeExtensionOnly() {
        require(ILiquidityMiningExtension(_extension).active(), "not active extension");
        _;
    }

    /** @dev activeSetupOnly modifier used to check for function calls only if the setup is active. */
    modifier activeSetupOnly(uint256 setupIndex) {
        require(_setups[setupIndex].active, "Setup not active");
        require(_setups[setupIndex].startBlock >= block.number && _setups[setupIndex].endBlock < block.number, "Invalid setup");
        _;
    }

    /** Extension methods */

    /** @dev initializes the liquidity mining contract.
      * @param extension extension address.
      * @param extensionInitData lm extension init payload.
      * @param orchestrator address of the eth item orchestrator.
      * @param rewardTokenAddress address of the reward token.
      * @return extensionReturnCall result of the extension initialization function, if it was called.  
     */
    function init(address extension, bytes memory extensionInitData, address orchestrator, address rewardTokenAddress, bytes memory liquidityMiningSetupInfosBytes, bool setPinned, uint256 pinnedIndex) public returns(bytes memory extensionReturnCall) {
        require(_factory == address(0), "Already initialized");
        require((_extension = extension) != address(0), "extension");
        _factory = msg.sender;
        emit RewardToken(_rewardTokenAddress = rewardTokenAddress);
        if (keccak256(extensionInitData) != keccak256("")) {
            extensionReturnCall = _call(_extension, extensionInitData);
        }
        (_liquidityFarmTokenCollection,) = IEthItemOrchestrator(orchestrator).createNative(abi.encodeWithSignature("init(string,string,bool,string,address,bytes)", "Covenants Farming", "cFARM", true, ILiquidityMiningFactory(_factory).getLiquidityFarmTokenCollectionURI(), address(this), ""), "");

        LiquidityMiningSetupInfo[] memory liquidityMiningSetupInfos = abi.decode(liquidityMiningSetupInfosBytes, (LiquidityMiningSetupInfo[]));
        require(liquidityMiningSetupInfos.length > 0, "Invalid length");
        for(uint256 i = 0; i < liquidityMiningSetupInfos.length; i++) {
            _setOrAddLiquidityMiningSetupInfo(liquidityMiningSetupInfos[i], true, false, 0);
        }
        _configurePinned(false, setPinned, pinnedIndex);

    }

    function setLiquidityMiningSetups(LiquidityMiningSetupConfiguration[] memory liquidityMiningSetups, bool clearPinned, bool setPinned, uint256 pinnedIndex) public override byExtension {
        for (uint256 i = 0; i < liquidityMiningSetups.length; i++) {
            _setOrAddLiquidityMiningSetupInfo(liquidityMiningSetups[i].info, liquidityMiningSetups[i].add, liquidityMiningSetups[i].disable, liquidityMiningSetups[i].index);
        }
        _configurePinned(clearPinned, setPinned, pinnedIndex);
    }

    function flushExcess() public returns(bool success) {
        if (_positionsCount == 0 && _rewardReceived > 0) {
            success = false;
        } else {
            for (uint256 i = 0; i < _setups.length; i++) {
                success = !_setups[i].active && _setups[i].startBlock < block.number && block.number > _setups[i].endBlock;
                if (!success) break;
            }
            if (success && _rewardReceived - _rewardPaid > 0) {
                _giveBack(_rewardReceived - _rewardPaid);
            }
        }
    }

    /** Public getters */

    function openPosition(LiquidityMiningPositionRequest memory request) public payable activeExtensionOnly activeSetupOnly(request.setupIndex) returns(uint256 positionId) {
        // retrieve the setup
        LiquidityMiningSetup storage chosenSetup = _setups[request.setupIndex];
        (IAMM amm, uint256 liquidityPoolAmount, uint256 mainTokenAmount) = _transferToMeAndCheckAllowance(chosenSetup, request);
        // retrieve the unique owner
        address uniqueOwner = (request.positionOwner != address(0)) ? request.positionOwner : msg.sender;
        // create the position id
        positionId = uint256(keccak256(abi.encode(uniqueOwner, request.setupIndex)));
        // create the lp data for the amm
        LiquidityPoolData memory liquidityPoolData = LiquidityPoolData(
            chosenSetup.info.liquidityPoolTokenAddress,
            request.amountIsLiquidityPool ? liquidityPoolAmount : mainTokenAmount,
            chosenSetup.info.mainTokenAddress,
            request.amountIsLiquidityPool,
            chosenSetup.info.involvingETH,
            address(this)
        );
        // check the input amount
        if (!liquidityPoolData.amountIsLiquidityPool) {
            // retrieve the poolTokenAmount from the amm
            liquidityPoolData.involvingETH ? (liquidityPoolData.amount,,) = amm.addLiquidity{value : msg.value}(liquidityPoolData) : (liquidityPoolData.amount,,) = amm.addLiquidity(liquidityPoolData);
            liquidityPoolData.amountIsLiquidityPool = true;
        } else {
            require(msg.value == 0, "ETH not involved");
        }
        // calculate the reward
        uint256 reward;
        uint256 lockedRewardPerBlock;
        if (!chosenSetup.info.free) {
            (reward, lockedRewardPerBlock) = calculateLockedLiquidityMiningSetupReward(request.setupIndex, mainTokenAmount, false, 0);
            require(reward > 0 && lockedRewardPerBlock > 0, "Insufficient staked amount");
            chosenSetup.totalSupply += mainTokenAmount;
            _mintLiquidity(uniqueOwner, liquidityPoolData.amount, request.setupIndex);
        }
        _positions[positionId] = LiquidityMiningPosition({
            uniqueOwner: uniqueOwner,
            setupIndex : request.setupIndex,
            setupStartBlock: chosenSetup.startBlock,
            setupEndBlock: chosenSetup.endBlock,
            liquidityPoolTokenAmount: liquidityPoolData.amount,
            mainTokenAmount: mainTokenAmount,
            reward: reward,
            lockedRewardPerBlock: lockedRewardPerBlock,
            creationBlock: block.number
        });
        _positionsCount += 1;
        if (chosenSetup.info.free) {
            _updateFreeSetup(request.setupIndex, liquidityPoolData.amount, positionId, 0, false);
        } else if (_hasPinned && _setups[_pinnedSetupIndex].info.free) {
            _updateFreeSetup(_pinnedSetupIndex, 0, 0, lockedRewardPerBlock, false);
        }

        emit Transfer(positionId, address(0), uniqueOwner);
    }

    function addLiquidity(uint256 positionId, LiquidityMiningPositionRequest memory request) public payable activeExtensionOnly activeSetupOnly(request.setupIndex) byPositionOwner(positionId) {
        // retrieve liquidity mining position
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionId];
        LiquidityMiningSetup memory chosenSetup = _setups[liquidityMiningPosition.setupIndex];
        // check if liquidity mining position is valid
        require(chosenSetup.info.free, "Invalid add liquidity");
        (IAMM amm, uint256 liquidityPoolAmount, uint256 mainTokenAmount) = _transferToMeAndCheckAllowance(chosenSetup, request);
        // liquidity pool data struct for the AMM
        LiquidityPoolData memory liquidityPoolData = LiquidityPoolData(
            chosenSetup.info.liquidityPoolTokenAddress,
            request.amountIsLiquidityPool ? liquidityPoolAmount : mainTokenAmount,
            chosenSetup.info.mainTokenAddress,
            request.amountIsLiquidityPool,
            chosenSetup.info.involvingETH,
            address(this)
        );
        // amount is lp check
        if (!liquidityPoolData.amountIsLiquidityPool) {
            // retrieve the poolTokenAmount from the amm
            if(liquidityPoolData.involvingETH) {
                (liquidityPoolData.amount,,) = amm.addLiquidity{value : msg.value}(liquidityPoolData);
            } else {
                (liquidityPoolData.amount,,) = amm.addLiquidity(liquidityPoolData);
            }
            liquidityPoolData.amountIsLiquidityPool = true;
        } else {
            require(msg.value == 0, "ETH not involved");
        }
        // rebalance the reward per token
        _rewardPerTokenPerSetup[request.setupIndex] += (((block.number - chosenSetup.lastUpdateBlock) * chosenSetup.rewardPerBlock) * 1e18) / chosenSetup.totalSupply;
        liquidityMiningPosition.reward = calculateFreeLiquidityMiningSetupReward(positionId, false);
        _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[request.setupIndex];
        // update the last block update variable
        chosenSetup.lastUpdateBlock = block.number;
        chosenSetup.totalSupply += liquidityPoolData.amount;
    }

    /** @dev this function allows a user to withdraw the reward.
      * @param positionId liquidity mining position id.
     */
    function withdrawReward(uint256 positionId) public byPositionOwner(positionId) {
        // retrieve liquidity mining position
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionId];
        uint256 reward = liquidityMiningPosition.reward;
        if (!_setups[liquidityMiningPosition.setupIndex].info.free) {
            // check if reward is available
            require(liquidityMiningPosition.reward > 0, "No reward");
            // check if it's a partial reward or not
            if (_setups[liquidityMiningPosition.setupIndex].endBlock > block.number) {
                // calculate the reward from the liquidity mining position creation block to the current block multiplied by the reward per block
                (reward,) = calculateLockedLiquidityMiningSetupReward(0, 0, true, positionId);
            }
            require(reward <= liquidityMiningPosition.reward, "Reward is bigger than expected");
            // remove the partial reward from the liquidity mining position total reward
            liquidityMiningPosition.reward = liquidityMiningPosition.reward - reward;
        } else {
            // rebalance setup
            _rewardPerTokenPerSetup[liquidityMiningPosition.setupIndex] += (((block.number - _setups[liquidityMiningPosition.setupIndex].lastUpdateBlock) * _setups[liquidityMiningPosition.setupIndex].rewardPerBlock) * 1e18) / _setups[liquidityMiningPosition.setupIndex].totalSupply;
             // update the last block update variable
            _setups[liquidityMiningPosition.setupIndex].lastUpdateBlock = block.number;
            reward = calculateFreeLiquidityMiningSetupReward(positionId, false);
            _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[liquidityMiningPosition.setupIndex];
            require(reward > 0, "No reward?");
            liquidityMiningPosition.reward = 0;
        }
        // transfer the reward
        if (reward > 0) {
            _rewardTokenAddress != address(0) ? _safeTransfer(_rewardTokenAddress, liquidityMiningPosition.uniqueOwner, reward) : payable(liquidityMiningPosition.uniqueOwner).transfer(reward);
            _rewardPaid += reward;
        }
        // update the creation block for the position
        liquidityMiningPosition.creationBlock = block.number;
        if (!_setups[liquidityMiningPosition.setupIndex].info.free && liquidityMiningPosition.reward == 0) {
            // the locked setup must be considered finished
            if (_setups[liquidityMiningPosition.setupIndex].active && _hasPinned && _setups[_pinnedSetupIndex].info.free) {
                _updateFreeSetup(_pinnedSetupIndex, 0, 0, _setups[liquidityMiningPosition.setupIndex].rewardPerBlock - ((_setups[liquidityMiningPosition.setupIndex].rewardPerBlock * (_setups[liquidityMiningPosition.setupIndex].totalSupply * 1e18 / _setups[liquidityMiningPosition.setupIndex].info.maxStakeable)) / 1e18), true);
            }
            // close the locked position after withdrawing all the reward
            delete _positions[positionId];
            _positionsCount -= 1;
        } else if (!_setups[liquidityMiningPosition.setupIndex].info.free) {
            // set the partially redeemed amount
            _partiallyRedeemed[positionId] += reward;
        }
    }

    function withdrawLiquidity(uint256 positionId, uint256 objectId, bool unwrapPair, uint256 removedLiquidity) public {
        // retrieve liquidity mining position
        LiquidityMiningPosition memory liquidityMiningPosition = _positions[positionId];
        uint256 setupIndex = liquidityMiningPosition.setupIndex;
        if (objectId != 0) {
            if(address(INativeV1(_liquidityFarmTokenCollection).asInteroperable(objectId)) != address(0)) {
                setupIndex = _objectIdSetup[objectId];
            }
        }
        require((positionId != 0 && objectId == 0) || (objectId != 0 && positionId == 0 && _setups[setupIndex].objectId == objectId), "Invalid position");
        // current owned liquidity
        require(
            (
                _setups[setupIndex].info.free && 
                liquidityMiningPosition.creationBlock != 0 &&
                removedLiquidity <= liquidityMiningPosition.liquidityPoolTokenAmount &&
                liquidityMiningPosition.uniqueOwner == msg.sender
            ) || INativeV1(_liquidityFarmTokenCollection).balanceOf(msg.sender, objectId) >= removedLiquidity, "Invalid withdraw");
        // check if liquidity mining position is valid
        require(_setups[setupIndex].info.free || (_setups[setupIndex].endBlock <= block.number), "Invalid withdraw");
        // burn the liquidity in the locked setup
        if (positionId == 0) {
            _burnLiquidity(objectId, removedLiquidity);
        } else {
            withdrawReward(positionId);
            _setups[liquidityMiningPosition.setupIndex].totalSupply -= removedLiquidity;
            _setups[liquidityMiningPosition.setupIndex].lastUpdateBlock = block.number;
        }
        _removeLiquidity(positionId, setupIndex, unwrapPair, removedLiquidity, false);
    }

    function unlock(uint256 positionId, bool unwrapPair) public payable byPositionOwner(positionId) {
        // retrieve liquidity mining position
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionId];
        require(!_setups[liquidityMiningPosition.setupIndex].info.free && liquidityMiningPosition.setupEndBlock > block.number, "Invalid unlock");
        uint256 rewardToGiveBack = _partiallyRedeemed[positionId];
        // must pay a penalty fee
        rewardToGiveBack += _setups[liquidityMiningPosition.setupIndex].info.penaltyFee == 0 ? 0 : (liquidityMiningPosition.reward * ((_setups[liquidityMiningPosition.setupIndex].info.penaltyFee * 1e18) / ONE_HUNDRED) / 1e18);
        // add all the unissued reward
        uint256 positionRewardPerBlock = _setups[liquidityMiningPosition.setupIndex].rewardPerBlock * (((liquidityMiningPosition.mainTokenAmount * 1e18) / _setups[liquidityMiningPosition.setupIndex].info.maxStakeable) / 1e18);
        rewardToGiveBack += (block.number - liquidityMiningPosition.creationBlock) * positionRewardPerBlock;
        if (rewardToGiveBack > 0) {
            _giveBack(rewardToGiveBack);
        }
        _setups[liquidityMiningPosition.setupIndex].totalSupply -= liquidityMiningPosition.mainTokenAmount;
        _burnLiquidity(_setups[liquidityMiningPosition.setupIndex].objectId, liquidityMiningPosition.liquidityPoolTokenAmount);
        _removeLiquidity(positionId, liquidityMiningPosition.setupIndex, unwrapPair, liquidityMiningPosition.liquidityPoolTokenAmount, true);
        _setups[liquidityMiningPosition.setupIndex].startBlock = block.number;
    }

    function calculateLockedLiquidityMiningSetupReward(uint256 setupIndex, uint256 mainTokenAmount, bool isPartial, uint256 positionId) public view returns(uint256 reward, uint256 relativeRewardPerBlock) {
        if (isPartial) {
            // retrieve the position
            LiquidityMiningPosition memory liquidityMiningPosition = _positions[positionId];
            // calculate the reward
            reward = (block.number >= _setups[liquidityMiningPosition.setupIndex].endBlock) ? liquidityMiningPosition.reward : ((block.number - liquidityMiningPosition.creationBlock) * liquidityMiningPosition.lockedRewardPerBlock);
        } else {
            LiquidityMiningSetup memory setup = _setups[setupIndex];
            // check if main token amount is less than the stakeable liquidity
            require(mainTokenAmount <= setup.info.maxStakeable - setup.totalSupply, "Invalid liquidity");
            uint256 remainingBlocks = block.number > setup.endBlock ? 0 : setup.endBlock - block.number;
            // get amount of remaining blocks
            require(remainingBlocks > 0, "LiquidityMiningSetup ended");
            // get total reward still available (= 0 if rewardPerBlock = 0)
            require(setup.rewardPerBlock * remainingBlocks > 0, "No rewards");
            // calculate relativeRewardPerBlock
            relativeRewardPerBlock = (setup.rewardPerBlock * ((mainTokenAmount * 1e18) / setup.info.maxStakeable)) / 1e18;
            // check if rewardPerBlock is greater than 0
            require(relativeRewardPerBlock > 0, "Invalid rpb");
            // calculate reward by multiplying relative reward per block and the remaining blocks
            reward = relativeRewardPerBlock * remainingBlocks;
        }
    }

    function calculateFreeLiquidityMiningSetupReward(uint256 positionId, bool isExt) public view returns(uint256 reward) {
        LiquidityMiningPosition memory liquidityMiningPosition = _positions[positionId];
        reward = ((_rewardPerTokenPerSetup[liquidityMiningPosition.setupIndex] - _rewardPerTokenPaid[positionId]) * liquidityMiningPosition.liquidityPoolTokenAmount) / 1e18;
        if (isExt) {
            uint256 rpt = (((block.number - _setups[liquidityMiningPosition.setupIndex].startBlock) * _setups[liquidityMiningPosition.setupIndex].rewardPerBlock) * 1e18) / _setups[liquidityMiningPosition.setupIndex].totalSupply;
            reward += ((rpt - _rewardPerTokenPaid[positionId]) * liquidityMiningPosition.liquidityPoolTokenAmount) / 1e18;
        }
        reward += liquidityMiningPosition.reward;
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public view override returns(bytes4) {
        require(_liquidityFarmTokenCollection == msg.sender, "Invalid sender");
        return this.onERC1155BatchReceived.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public view override returns(bytes4) {
        require(_liquidityFarmTokenCollection == msg.sender, "Invalid sender");
        return this.onERC1155Received.selector;
    }

    /** Private methods */

    function _transferToMeAndCheckAllowance(LiquidityMiningSetup memory setup, LiquidityMiningPositionRequest memory request) private returns(IAMM amm, uint256 liquidityPoolAmount, uint256 mainTokenAmount) {
        require(request.amount > 0, "No amount");
        // retrieve the values
        amm = IAMM(setup.info.ammPlugin);
        liquidityPoolAmount = request.amountIsLiquidityPool ? request.amount : 0;
        mainTokenAmount = request.amountIsLiquidityPool ? 0 : request.amount;
        address[] memory tokens;
        uint256[] memory tokenAmounts;
        // if liquidity pool token amount is provided, the position is opened by liquidity pool token amount
        if(request.amountIsLiquidityPool) {
            _safeTransferFrom(setup.info.liquidityPoolTokenAddress, msg.sender, address(this), liquidityPoolAmount);
            (tokenAmounts, tokens) = amm.byLiquidityPoolAmount(setup.info.liquidityPoolTokenAddress, liquidityPoolAmount);
        } else {
            // else it is opened by the tokens amounts
            (liquidityPoolAmount, tokenAmounts, tokens) = amm.byTokenAmount(setup.info.liquidityPoolTokenAddress, setup.info.mainTokenAddress, mainTokenAmount);
        }

        // iterate the tokens and perform the transferFrom and the approve
        for(uint256 i = 0; i < tokens.length; i++) {
            if(tokens[i] == setup.info.mainTokenAddress) {
                mainTokenAmount = tokenAmounts[i];
                if(request.amountIsLiquidityPool) {
                    break;
                }
            }
            if(request.amountIsLiquidityPool) {
                continue;
            }
            if(setup.info.involvingETH && setup.info.ethereumAddress == tokens[i]) {
                require(msg.value == tokenAmounts[i], "Incorrect eth value");
            } else {
                _safeTransferFrom(tokens[i], msg.sender, address(this), tokenAmounts[i]);
                _safeApprove(tokens[i], setup.info.ammPlugin, tokenAmounts[i]);
            }
        }
    }

    /** @dev mints a new PositionToken inside the collection for the given wallet.
      * @param uniqueOwner liquidityMiningPosition token extension.
      * @param amount amount of to mint for a farm token.
      * @param setupIndex index of the setup.
      * @return objectId new liquidityMiningPosition token object id.
     */
    function _mintLiquidity(address uniqueOwner, uint256 amount, uint256 setupIndex) private returns(uint256 objectId) {
        if (_setups[setupIndex].objectId == 0) {
            (objectId,) = INativeV1(_liquidityFarmTokenCollection).mint(amount, string(abi.encodePacked("Farming LP ", _toString(_setups[setupIndex].info.liquidityPoolTokenAddress))), "fLP", ILiquidityMiningFactory(_factory).getLiquidityFarmTokenURI(), true);
            emit FarmToken(objectId, _setups[setupIndex].info.liquidityPoolTokenAddress, setupIndex, _setups[setupIndex].endBlock);
            _objectIdSetup[objectId] = setupIndex;
            _setups[setupIndex].objectId = objectId;
        } else {
            INativeV1(_liquidityFarmTokenCollection).mint(_setups[setupIndex].objectId, amount);
        }
        INativeV1(_liquidityFarmTokenCollection).safeTransferFrom(address(this), uniqueOwner, _setups[setupIndex].objectId, amount, "");
    }

    /** @dev burns a farm token from the collection.
      * @param objectId object id where to burn liquidity.
      * @param amount amount of liquidity to burn.
      */
    function _burnLiquidity(uint256 objectId, uint256 amount) private {
        INativeV1 tokenCollection = INativeV1(_liquidityFarmTokenCollection);
        // transfer the liquidity mining farm token to this contract
        tokenCollection.safeTransferFrom(msg.sender, address(this), objectId, amount, "");
        // burn the liquidity mining farm token
        tokenCollection.burn(objectId, amount);
    }


    /** @dev helper function used to remove liquidity from a free position or to burn item liquidity tokens and retrieve their content.
      * @param positionId id of the position.
      * @param setupIndex index of the setup related to the item liquidity tokens.
      * @param unwrapPair whether to unwrap the liquidity pool tokens or not.
      * @param isUnlock if we're removing liquidity from an unlock method or not.
     */
    function _removeLiquidity(uint256 positionId, uint256 setupIndex, bool unwrapPair, uint256 removedLiquidity, bool isUnlock) private {
        // create liquidity pool data struct for the AMM
        LiquidityPoolData memory lpData = LiquidityPoolData(
            _setups[setupIndex].info.liquidityPoolTokenAddress,
            removedLiquidity,
            _setups[setupIndex].info.mainTokenAddress,
            true,
            _setups[setupIndex].info.involvingETH,
            msg.sender
        );
        // retrieve the position
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionId];
        // remaining liquidity
        uint256 remainingLiquidity;
        // we are removing liquidity using the setup items
        if (_setups[liquidityMiningPosition.setupIndex].info.free && liquidityMiningPosition.creationBlock != 0 && positionId != 0) {
            // update the remaining liquidity
            remainingLiquidity = liquidityMiningPosition.liquidityPoolTokenAmount - removedLiquidity;
        }
        // retrieve fee stuff
        (uint256 exitFeePercentage, address exitFeeWallet) = ILiquidityMiningFactory(_factory).feePercentageInfo();
        // pay the fees!
        if (exitFeePercentage > 0) {
            uint256 fee = (lpData.amount * ((exitFeePercentage * 1e18) / ONE_HUNDRED)) / 1e18;
            _safeTransfer(_setups[setupIndex].info.liquidityPoolTokenAddress, exitFeeWallet, fee);
            lpData.amount = lpData.amount - fee;
        }
        // check if the user wants to unwrap its pair or not
        if (unwrapPair) {
            // remove liquidity using AMM
            address ammPlugin = _setups[setupIndex].info.ammPlugin;
            _safeApprove(lpData.liquidityPoolAddress, ammPlugin, lpData.amount);
            (, uint256[] memory amounts, address[] memory tokens) = IAMM(ammPlugin).removeLiquidity(lpData);
            if (isUnlock) {
                for (uint256 i = 0; i < tokens.length; i++) {
                    if (tokens[i] == _setups[setupIndex].info.mainTokenAddress) {
                        _setups[setupIndex].totalSupply -= amounts[0];
                        break;
                    }
                }
            }
        } else {
            // send back the liquidity pool token amount without the fee
            _safeTransfer(lpData.liquidityPoolAddress, lpData.receiver, lpData.amount);
        }
        // rebalance the setup if not free
        if (!_setups[setupIndex].info.free && _setups[setupIndex].active) {
            // check if it's finished (this is a withdraw) or not (a unlock)
            if (isUnlock && _hasPinned && _setups[_pinnedSetupIndex].info.free) {
                // this is an unlock, so we just need to provide back the reward per block
                if (_setups[_pinnedSetupIndex].totalSupply != 0) {
                    _rewardPerTokenPerSetup[_pinnedSetupIndex] += (((block.number - _setups[_pinnedSetupIndex].lastUpdateBlock) * _setups[_pinnedSetupIndex].rewardPerBlock) * 1e18) / _setups[_pinnedSetupIndex].totalSupply;
                    // update the last block update variable
                    _setups[_pinnedSetupIndex].lastUpdateBlock = block.number;
                }
                _setups[_pinnedSetupIndex].rewardPerBlock += _setups[setupIndex].rewardPerBlock * ((removedLiquidity * 1e18 / _setups[setupIndex].info.maxStakeable) / 1e18);
            } else if (!isUnlock && liquidityMiningPosition.setupStartBlock == _setups[setupIndex].startBlock) {
                // the locked setup must be considered finished
                if (_hasPinned && _setups[_pinnedSetupIndex].info.free) {
                    if (_setups[setupIndex].totalSupply != 0) {
                        _rewardPerTokenPerSetup[setupIndex] += (((block.number - _setups[setupIndex].lastUpdateBlock) * _setups[setupIndex].rewardPerBlock) * 1e18) / _setups[setupIndex].totalSupply;
                    }
                    // update the last block update variable
                    _setups[_pinnedSetupIndex].lastUpdateBlock = block.number;
                    _setups[_pinnedSetupIndex].rewardPerBlock -= _setups[setupIndex].rewardPerBlock - ((_setups[setupIndex].rewardPerBlock * (_setups[setupIndex].totalSupply * 1e18 / _setups[setupIndex].info.maxStakeable)) / 1e18);
                } else {
                    _toggleSetup(setupIndex);
                }
            }
        } else if (_setups[liquidityMiningPosition.setupIndex].info.free && positionId != 0) {
            // delete the liquidity mining position after the withdraw
            if (remainingLiquidity == 0) {
                delete _positions[positionId];
                _positionsCount -= 1;
            } else {
                // update the creation block and amount
                liquidityMiningPosition.creationBlock = block.number;
                liquidityMiningPosition.liquidityPoolTokenAmount = remainingLiquidity;
            }
            // check if setup is marked as finished or not
            if (_setups[liquidityMiningPosition.setupIndex].active && _setups[liquidityMiningPosition.setupIndex].startBlock == liquidityMiningPosition.setupStartBlock && _setups[liquidityMiningPosition.setupIndex].endBlock >= block.number) {
                _toggleSetup(liquidityMiningPosition.setupIndex);
            }
        }
    }

    function _setOrAddLiquidityMiningSetupInfo(LiquidityMiningSetupInfo memory info, bool add, bool disable, uint256 setupIndex) private {
        LiquidityMiningSetup storage setup = _setups[setupIndex];
        LiquidityMiningSetupInfo memory liquidityMiningSetupInfo = add ? info : setup.info;
        require(
            liquidityMiningSetupInfo.ammPlugin != address(0) &&
            liquidityMiningSetupInfo.liquidityPoolTokenAddress != address(0) &&
            liquidityMiningSetupInfo.originalRewardPerBlock > 0 &&
            (liquidityMiningSetupInfo.free || liquidityMiningSetupInfo.maxStakeable > 0),
            "Invalid setup configuration"
        );
        if(add || !disable) {
            liquidityMiningSetupInfo.renewTimes = liquidityMiningSetupInfo.renewTimes + 1;
            if(liquidityMiningSetupInfo.renewTimes == 0) {
                liquidityMiningSetupInfo.renewTimes = liquidityMiningSetupInfo.renewTimes - 1;
            }
        }

        if (add) {
            address mainTokenAddress = liquidityMiningSetupInfo.mainTokenAddress;
            address ammPlugin = liquidityMiningSetupInfo.ammPlugin;
            (,,address[] memory tokenAddresses) = IAMM(ammPlugin).byLiquidityPool(liquidityMiningSetupInfo.liquidityPoolTokenAddress);
            liquidityMiningSetupInfo.ethereumAddress = address(0);
            if(liquidityMiningSetupInfo.involvingETH) {
                (liquidityMiningSetupInfo.ethereumAddress,,) = IAMM(ammPlugin).data();
            }
            bool mainTokenFound = false;
            bool ethTokenFound = false;
            for(uint256 z = 0; z < tokenAddresses.length; z++) {
                if(tokenAddresses[z] == mainTokenAddress) {
                    mainTokenFound = true;
                } else {
                    emit SetupToken(mainTokenAddress, tokenAddresses[z]);
                    if(tokenAddresses[z] == liquidityMiningSetupInfo.ethereumAddress) {
                        ethTokenFound = true;
                    }
                }
            }
            require(mainTokenFound, "No main token");
            require(!liquidityMiningSetupInfo.involvingETH || ethTokenFound, "No ETH token");
            _setups.push(LiquidityMiningSetup(liquidityMiningSetupInfo, false, 0, 0, 0, 0, liquidityMiningSetupInfo.originalRewardPerBlock, 0));
            return;
        }

        if(disable) {
            require(setup.active, "Not possible");
            require(!_hasPinned || _pinnedSetupIndex != setupIndex, "Invalid");
            setup.active = false;
            setup.endBlock = block.number;
            liquidityMiningSetupInfo.renewTimes = 0;
            setup.info = liquidityMiningSetupInfo;
            return;
        }

        require(liquidityMiningSetupInfo.free && (!_hasPinned || setupIndex != _pinnedSetupIndex), "Cannot edit");

        if (setup.active && setup.endBlock < block.number) {
            setup = _setups[setupIndex];
            uint256 difference = info.originalRewardPerBlock < liquidityMiningSetupInfo.originalRewardPerBlock ? liquidityMiningSetupInfo.originalRewardPerBlock - info.originalRewardPerBlock : info.originalRewardPerBlock - liquidityMiningSetupInfo.originalRewardPerBlock;
            uint256 duration = setup.endBlock - block.number;
            uint256 amount = difference * duration;
            if (amount > 0) {
                _updateFreeSetup(setupIndex, 0, 0, difference, info.originalRewardPerBlock < liquidityMiningSetupInfo.originalRewardPerBlock);
            }
        }
        liquidityMiningSetupInfo.originalRewardPerBlock = info.originalRewardPerBlock;
        setup.info = liquidityMiningSetupInfo;
    }

    function _updateFreeSetup(uint256 setupIndex, uint256 amount, uint256 positionId, uint256 lockedRewardPerBlock, bool fromExit) private {
        if (_setups[setupIndex].totalSupply != 0) {
            _rewardPerTokenPerSetup[setupIndex] += (((block.number - _setups[setupIndex].lastUpdateBlock) * _setups[setupIndex].rewardPerBlock) * 1e18) / _setups[setupIndex].totalSupply;
        }
        // update the last block update variable
        _setups[setupIndex].lastUpdateBlock = block.number;
        if (positionId != 0) {
            _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[setupIndex];
        }
        if (amount > 0) {
            fromExit ? _setups[setupIndex].totalSupply -= amount : _setups[setupIndex].totalSupply += amount;
        }
        if (lockedRewardPerBlock > 0) {
            fromExit ? _setups[setupIndex].rewardPerBlock -= amount : _setups[setupIndex].rewardPerBlock += amount;
        }
    }

    function _configurePinned(bool clearPinned, bool setPinned, uint256 pinnedIndex) private {
        if (clearPinned && _hasPinned) {
            _hasPinned = false;
            _updateFreeSetup(_pinnedSetupIndex, 0, 0, _setups[_pinnedSetupIndex].rewardPerBlock - _setups[_pinnedSetupIndex].info.originalRewardPerBlock, true);
            if(_setups[_pinnedSetupIndex].endBlock <= block.number) {
                _setups[_pinnedSetupIndex].active = false;
                _toggleSetup(_pinnedSetupIndex);
            }
        }
        // check if we're updating the pinned setup
        if (!clearPinned && setPinned) {
            require(!_hasPinned && _setups[pinnedIndex].info.free && _setups[pinnedIndex].active, "Invalid");
            if(_setups[pinnedIndex].totalSupply == 0) {
                _setups[pinnedIndex].startBlock = block.number;
            }
            // update pinned setup index
            _hasPinned = true;
            _pinnedSetupIndex = pinnedIndex;
            uint256 oldPinnedSurplus = 0;
            for (uint256 i = 0; i < _setups.length; i++) {
                if (!_setups[i].info.free && _setups[i].active && block.number >= _setups[i].startBlock && block.number < _setups[i].endBlock) {
                    oldPinnedSurplus += _setups[i].rewardPerBlock - ((_setups[i].rewardPerBlock * (_setups[i].totalSupply * 1e18 / _setups[i].info.maxStakeable)) / 1e18);
                }
                LiquidityMiningSetup storage lockedSetup = _setups[i];
                if (lockedSetup.info.free || !lockedSetup.active) continue;
                if (lockedSetup.endBlock < block.number) {
                    lockedSetup.active = false;
                    _toggleSetup(i);
                }
            }
            _setups[_pinnedSetupIndex].rewardPerBlock = _setups[_pinnedSetupIndex].info.originalRewardPerBlock;
            _updateFreeSetup(_pinnedSetupIndex, 0, 0, oldPinnedSurplus, false);
        }
    }

    function _toggleSetup(uint256 setupIndex) private {
        LiquidityMiningSetup storage setup = _setups[setupIndex];
        require(!setup.active || block.number >= setup.endBlock, "Not valid activation");

        if (setup.active && block.number >= setup.endBlock) {
            if (!setup.info.free && _hasPinned) {
                _setups[_pinnedSetupIndex].rewardPerBlock -= ( _setups[setupIndex].rewardPerBlock - _setups[setupIndex].rewardPerBlock * (((_setups[setupIndex].totalSupply * 1e18) /  _setups[setupIndex].info.maxStakeable) / 1e18));
            }
            if (setup.info.renewTimes == 0) {
                setup.active = false;
                if(_hasPinned && setupIndex == _pinnedSetupIndex) {
                    _hasPinned = false;
                    setup.rewardPerBlock = setup.info.originalRewardPerBlock;
                }
                return;
            }
        }

        if (!setup.info.free) {
            // count the number of currently active locked setups
            uint256 count = 0;
            for(uint256 i = 0; i < _setups.length; i++) {
                if(_setups[i].info.free || i == setupIndex) continue;
                if(_setups[i].active) {
                    // increase the counter
                    count++;
                }
            }
            // set the setup as not renewable
            if(count > MAX_CONTEMPORARY_LOCKED) {
                setup.info.renewTimes = 0;
                setup.active = false;
                return;
            }
        }

        setup.active = _ensureTransfer(setup.rewardPerBlock * setup.info.blockDuration);
        if (setup.active) {
            _rewardReceived += setup.rewardPerBlock * setup.info.blockDuration;
            setup.info.renewTimes -= 1;
            setup.startBlock = block.number;
            setup.endBlock = setup.startBlock + setup.info.blockDuration;
            setup.totalSupply = 0;
            if (!setup.info.free && _hasPinned) {
                _setups[_pinnedSetupIndex].rewardPerBlock += setup.rewardPerBlock;
            }
        } else {
            setup.info.renewTimes = 0;
        }
    }

    /** @dev function used to safely approve ERC20 transfers.
      * @param erc20TokenAddress address of the token to approve.
      * @param to receiver of the approval.
      * @param value amount to approve for.
     */
    function _safeApprove(address erc20TokenAddress, address to, uint256 value) internal virtual {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).approve.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'APPROVE_FAILED');
    }

    /** @dev function used to safe transfer ERC20 tokens.
      * @param erc20TokenAddress address of the token to transfer.
      * @param to receiver of the tokens.
      * @param value amount of tokens to transfer.
     */
    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) internal virtual {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFER_FAILED');
    }

    /** @dev this function safely transfers the given ERC20 value from an address to another.
      * @param erc20TokenAddress erc20 token address.
      * @param from address from.
      * @param to address to.
      * @param value amount to transfer.
     */
    function _safeTransferFrom(address erc20TokenAddress, address from, address to, uint256 value) private {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).transferFrom.selector, from, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFERFROM_FAILED');
    }

    /** @dev calls the contract at the given location using the given payload and returns the returnData.
      * @param location location to call.
      * @param payload call payload.
      * @return returnData call return data.
     */
    function _call(address location, bytes memory payload) private returns(bytes memory returnData) {
        assembly {
            let result := call(gas(), location, 0, add(payload, 0x20), mload(payload), 0, 0)
            let size := returndatasize()
            returnData := mload(0x40)
            mstore(returnData, size)
            let returnDataPayloadStart := add(returnData, 0x20)
            returndatacopy(returnDataPayloadStart, 0, size)
            mstore(0x40, add(returnDataPayloadStart, size))
            switch result case 0 {revert(returnDataPayloadStart, size)}
        }
    }

    function _ensureTransfer(uint256 amount) private returns(bool) {
        // uint256 initialBalance = _rewardTokenAddress == address(0) ? address(this).balance : IERC20(_rewardTokenAddress).balanceOf(address(this));
        // uint256 expectedBalance = initialBalance + amount;
        try ILiquidityMiningExtension(_extension).transferTo(amount) {
            return true;
        } catch {
            return false;
        }
        // uint256 actualBalance = _rewardTokenAddress == address(0) ? address(this).balance : IERC20(_rewardTokenAddress).balanceOf(address(this));
        //if(actualBalance == expectedBalance) {
        //    return true;
        //}
        //_giveBack(actualBalance - initialBalance);
        //return false;
    }

    /** @dev returns the input address to string.
      * @param _addr address to convert as string.
      * @return address as string.
     */
    function _toString(address _addr) internal pure returns(string memory) {
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

    /** @dev gives back the reward.
      * @param amount to give back.
     */
    function _giveBack(uint256 amount) private {
        if(amount == 0) {
            return;
        }
        if (_rewardTokenAddress == address(0)) {
            ILiquidityMiningExtension(_extension).backToYou{value : amount}(amount);
        } else {
            IERC20(_rewardTokenAddress).approve(_extension, amount);
            ILiquidityMiningExtension(_extension).backToYou(amount);
        }
    }
}