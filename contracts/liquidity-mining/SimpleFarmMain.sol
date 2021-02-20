//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../amm-aggregator/common/IAMM.sol";
import "./IFarmMain.sol";
import "./IFarmExtension.sol";
import "./IFarmFactory.sol";
import "./util/ERC1155Receiver.sol";
import "./util/IERC20.sol";
import "./util/IEthItemOrchestrator.sol";
import "./util/INativeV1.sol";

contract SimpleFarmMain is IFarmMain, ERC1155Receiver {

    // max number of contemporary locked
    uint256 public override constant MAX_CONTEMPORARY_LOCKED = 4;
    // percentage
    uint256 public override constant ONE_HUNDRED = 1e18;
    // event that tracks contracts deployed for the given reward token
    event RewardToken(address indexed rewardTokenAddress);
    // new or transferred farming position event
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
     // farm token collection
    address public _farmTokenCollection;
    // mapping containing all the currently available farming setups
    mapping(uint256 => FarmingSetup) private _setups;
    // counter for the farming setups
    uint256 private _farmingSetupsCount;
    // mapping containing all the positions
    mapping(uint256 => FarmingPosition) private _positions;
    // mapping containing the reward per token per setup per block
    mapping(uint256 => uint256) private _rewardPerTokenPerSetup;
    // mapping containing the reward per token paid per position
    mapping(uint256 => uint256) private _rewardPerTokenPaid;
    // mapping containing whether a liquidity mining position has been partially reedemed or not
    mapping(uint256 => uint256) private _partiallyRedeemed;
    // mapping containing object id to setup index
    mapping(uint256 => uint256) public _objectIdSetup;

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
        require(IFarmExtension(_extension).active(), "not active extension");
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
    function init(address extension, bytes memory extensionInitData, address orchestrator, address rewardTokenAddress, bytes memory farmingSetupInfosBytes) public returns(bytes memory extensionReturnCall) {
        require(_factory == address(0), "Already initialized");
        require((_extension = extension) != address(0), "extension");
        _factory = msg.sender;
        emit RewardToken(_rewardTokenAddress = rewardTokenAddress);
        if (keccak256(extensionInitData) != keccak256("")) {
            extensionReturnCall = _call(_extension, extensionInitData);
        }
        (_farmTokenCollection,) = IEthItemOrchestrator(orchestrator).createNative(abi.encodeWithSignature("init(string,string,bool,string,address,bytes)", "Covenants Farming", "cFARM", true, IFarmFactory(_factory).getFarmTokenCollectionURI(), address(this), ""), "");
        FarmingSetupInfo[] memory farmingSetupInfos = abi.decode(farmingSetupInfosBytes, (FarmingSetupInfo[]));
        require(farmingSetupInfos.length > 0, "Invalid length");
        for(uint256 i = 0; i < farmingSetupInfos.length; i++) {
            _setOrAddFarmingSetupInfo(farmingSetupInfos[i], true, false, 0);
        }
    }

    function setFarmingSetups(FarmingSetupConfiguration[] memory farmingSetups) public override byExtension {
        for (uint256 i = 0; i < farmingSetups.length; i++) {
            _setOrAddFarmingSetupInfo(farmingSetups[i].info, farmingSetups[i].add, farmingSetups[i].disable, farmingSetups[i].index);
        }
    }

    /** Public methods */

    /** @dev returns the position with the given id.
      * @param positionId id of the position.
      * @returns farming position with the given id.
     */
    function position(uint256 positionId) public view returns (FarmingPosition memory) {
        return _positions(positionId);
    }

    function setups() public view returns (FarmingSetup[] memory) {
        FarmingSetup[] memory setups = new FarmingSetup[](_farmingSetupsCount);
        for (uint256 i = 0; i < _farmingSetupsCount; i++) {
            setups[i] = _setups[i];
        }
        return setups;
    }

    function openPosition(FarmingPositionRequest memory request) public payable activeExtensionOnly activeSetupOnly(request.setupIndex) returns(uint256 positionId) {
        // retrieve the setup
        FarmingSetup storage chosenSetup = _setups[request.setupIndex];
        // retrieve the unique owner
        address uniqueOwner = (request.positionOwner != address(0)) ? request.positionOwner : msg.sender;
        // create the position id
        positionId = uint256(keccak256(abi.encode(uniqueOwner, request.setupIndex)));
        // create the lp data for the amm
        LiquidityPoolData memory liquidityPoolData = _addLiquidity(request.setupIndex, request);
        // calculate the reward
        uint256 reward;
        uint256 lockedRewardPerBlock;
        uint256 lastBlockUpdate = chosenSetup.lastBlockUpdate == 0 ? chosenSetup.startBlock : chosenSetup.lastBlockUpdate;
        if (!chosenSetup.info.free) {
            (reward, lockedRewardPerBlock) = calculateLockedFarmingReward(request.setupIndex, mainTokenAmount, false, 0);
            require(reward > 0 && lockedRewardPerBlock > 0, "Insufficient staked amount");
            uint256 rewardPerBlock = chosenSetup.rewardPerBlock - ((chosenSetup.rewardPerBlock * (chosenSetup.totalSupply * 1e18 / chosenSetup.info.maxStakeable)) / 1e18);
            _giveBack((block.number - lastBlockUpdate) * rewardPerBlock);
            chosenSetup.totalSupply += mainTokenAmount;
            _mintFarmTokenAmount(uniqueOwner, liquidityPoolData.amount, request.setupIndex);
        } else {
            if (chosenSetup.totalSupply == 0) {
                _giveBack((block.number - lastBlockUpdate) * chosenSetup.rewardPerBlock);
            }
            _updateFreeSetup(request.setupIndex, liquidityPoolData.amount, positionId, false);
        }
        _positions[positionId] = FarmingPosition({
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
        emit Transfer(positionId, address(0), uniqueOwner);
    }

    function addLiquidity(uint256 positionId, FarmingPositionRequest memory request) public payable activeExtensionOnly activeSetupOnly(request.setupIndex) byPositionOwner(positionId) {
        // retrieve farming position
        FarmingPosition storage farmingPosition = _positions[positionId];
        FarmingSetup memory chosenSetup = _setups[farmingPosition.setupIndex];
        // check if farmoing position is valid
        require(chosenSetup.info.free, "Invalid add liquidity");
        // create the lp data for the amm
        LiquidityPoolData memory liquidityPoolData = _addLiquidity(request.setupIndex, request);
        // rebalance the reward per token
        _rewardPerTokenPerSetup[request.setupIndex] += (((block.number - chosenSetup.lastUpdateBlock) * chosenSetup.rewardPerBlock) * 1e18) / chosenSetup.totalSupply;
        farmingPosition.reward = calculateFreeFarmingReward(positionId, false);
        _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[request.setupIndex];
        // update the last block update variable
        chosenSetup.lastUpdateBlock = block.number;
        chosenSetup.totalSupply += liquidityPoolData.amount;
    }


    /** @dev this function allows a user to withdraw the reward.
      * @param positionId farming position id.
     */
    function withdrawReward(uint256 positionId) public byPositionOwner(positionId) {
        // retrieve farming position
        FarmingPosition storage farmingPosition = _positions[positionId];
        uint256 reward = farmingPosition.reward;
        if (!_setups[farmingPosition.setupIndex].info.free) {
            // check if reward is available
            require(farmingPosition.reward > 0, "No reward");
            // check if it's a partial reward or not
            if (_setups[farmingPosition.setupIndex].endBlock > block.number) {
                // calculate the reward from the farming position creation block to the current block multiplied by the reward per block
                (reward,) = calculateLockedLiquidityMiningSetupReward(0, 0, true, positionId);
            }
            require(reward <= farmingPosition.reward, "Reward is bigger than expected");
            // remove the partial reward from the liquidity mining position total reward
            farmingPosition.reward = farmingPosition.reward - reward;
        } else {
            // rebalance setup
            _rewardPerTokenPerSetup[farmingPosition.setupIndex] += (((block.number - _setups[farmingPosition.setupIndex].lastUpdateBlock) * _setups[farmingPosition.setupIndex].rewardPerBlock) * 1e18) / _setups[farmingPosition.setupIndex].totalSupply;
             // update the last block update variable
            _setups[farmingPosition.setupIndex].lastUpdateBlock = block.number;
            reward = calculateFreeLiquidityMiningSetupReward(positionId, false);
            _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[farmingPosition.setupIndex];
            require(reward > 0, "No reward?");
            farmingPosition.reward = 0;
        }
        // transfer the reward
        if (reward > 0) {
            _rewardTokenAddress != address(0) ? _safeTransfer(_rewardTokenAddress, farmingPosition.uniqueOwner, reward) : payable(farmingPosition.uniqueOwner).transfer(reward);
        }
        if (!_setups[farmingPosition.setupIndex].info.free && farmingPosition.reward == 0) {
            // close the locked position after withdrawing all the reward
            delete _positions[positionId];
            if (_setups[farmingPosition.setupIndex].active) {
                _toggleSetup(farmingPosition.setupIndex);
            }
        } else if (!_setups[farmingPosition.setupIndex].info.free) {
            // set the partially redeemed amount
            _partiallyRedeemed[positionId] += reward;
        }
    }

    function withdrawLiquidity(uint256 positionId, uint256 objectId, bool unwrapPair, uint256 removedLiquidity) public {
        // retrieve farming position
        FarmingPosition memory farmingPosition = _positions[positionId];
        uint256 setupIndex = farmingPosition.setupIndex;
        if (objectId != 0 && address(INativeV1(_liquidityFarmTokenCollection).asInteroperable(objectId)) != address(0)) {
            setupIndex = _objectIdSetup[objectId];
        }
        require((positionId != 0 && objectId == 0) || (objectId != 0 && positionId == 0 && _setups[setupIndex].objectId == objectId), "Invalid position");
        // current owned liquidity
        require(
            (
                _setups[setupIndex].info.free && 
                farmingPosition.creationBlock != 0 &&
                removedLiquidity <= farmingPosition.liquidityPoolTokenAmount &&
                farmingPosition.uniqueOwner == msg.sender
            ) || INativeV1(_liquidityFarmTokenCollection).balanceOf(msg.sender, objectId) >= removedLiquidity, "Invalid withdraw");
        // check if liquidity mining position is valid
        require(_setups[setupIndex].info.free || (_setups[setupIndex].endBlock <= block.number), "Invalid withdraw");
        // burn the liquidity in the locked setup
        if (positionId == 0) {
            _burnLiquidity(objectId, removedLiquidity);
        } else {
            withdrawReward(positionId);
            _setups[farmingPosition.setupIndex].totalSupply -= removedLiquidity;
            _setups[farmingPosition.setupIndex].lastUpdateBlock = block.number;
        }
        _removeLiquidity(positionId, setupIndex, unwrapPair, removedLiquidity, false);
    }

    function unlock(uint256 positionId, bool unwrapPair) public payable byPositionOwner(positionId) {
        // retrieve liquidity mining position
        FarmingPosition storage farmingPosition = _positions[positionId];
        require(!_setups[farmingPosition.setupIndex].info.free && farmingPosition.setupEndBlock > block.number, "Invalid unlock");
        uint256 rewardToGiveBack = _partiallyRedeemed[positionId];
        // must pay a penalty fee
        rewardToGiveBack += _setups[farmingPosition.setupIndex].info.penaltyFee == 0 ? 0 : (farmingPosition.reward * ((_setups[farmingPosition.setupIndex].info.penaltyFee * 1e18) / ONE_HUNDRED) / 1e18);
        // add all the unissued reward
        uint256 positionRewardPerBlock = _setups[farmingPosition.setupIndex].rewardPerBlock * (((farmingPosition.mainTokenAmount * 1e18) / _setups[farmingPosition.setupIndex].info.maxStakeable) / 1e18);
        rewardToGiveBack += (block.number - farmingPosition.creationBlock) * positionRewardPerBlock;
        if (rewardToGiveBack > 0) {
            _giveBack(rewardToGiveBack);
        }
        _setups[farmingPosition.setupIndex].totalSupply -= farmingPosition.mainTokenAmount;
        _burnLiquidity(_setups[farmingPosition.setupIndex].objectId, farmingPosition.liquidityPoolTokenAmount);
        _removeLiquidity(positionId, farmingPosition.setupIndex, unwrapPair, farmingPosition.liquidityPoolTokenAmount, true);
    }

    function calculateLockedFarmingReward(uint256 setupIndex, uint256 mainTokenAmount, bool isPartial, uint256 positionId) public view returns(uint256 reward, uint256 relativeRewardPerBlock) {
        if (isPartial) {
            // retrieve the position
            FarmingPosition memory farmingPosition = _positions[positionId];
            // calculate the reward
            reward = (block.number >= _setups[farmingPosition.setupIndex].endBlock) ? farmingPosition.reward : ((block.number - farmingPosition.creationBlock) * farmingPosition.lockedRewardPerBlock);
        } else {
            FarmingSetup memory setup = _setups[setupIndex];
            // check if main token amount is less than the stakeable liquidity
            require(mainTokenAmount <= setup.info.maxStakeable - setup.totalSupply, "Invalid liquidity");
            uint256 remainingBlocks = block.number > setup.endBlock ? 0 : setup.endBlock - block.number;
            // get amount of remaining blocks
            require(remainingBlocks > 0, "FarmingSetup ended");
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

    function calculateFreeFarmingReward(uint256 positionId, bool isExt) public view returns(uint256 reward) {
        FarmingPosition memory farmingPosition = _positions[positionId];
        reward = ((_rewardPerTokenPerSetup[farmingPosition.setupIndex] - _rewardPerTokenPaid[positionId]) * farmingPosition.liquidityPoolTokenAmount) / 1e18;
        if (isExt) {
            uint256 rpt = (((block.number - _setups[farmingPosition.setupIndex].startBlock) * _setups[farmingPosition.setupIndex].rewardPerBlock) * 1e18) / _setups[farmingPosition.setupIndex].totalSupply;
            reward += ((rpt - _rewardPerTokenPaid[positionId]) * farmingPosition.liquidityPoolTokenAmount) / 1e18;
        }
        reward += farmingPosition.reward;
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public view override returns(bytes4) {
        require(_farmTokenCollection == msg.sender, "Invalid sender");
        return this.onERC1155BatchReceived.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public view override returns(bytes4) {
        require(_farmTokenCollection == msg.sender, "Invalid sender");
        return this.onERC1155Received.selector;
    }

    /** Private methods */

    function _setOrAddFarmingSetupInfo(FarmingSetupInfo memory info, bool add, bool disable, uint256 setupIndex) private {
        FarmingSetup storage setup = _setups[setupIndex];
        FarmingSetupInfo memory farmingSetupInfo = add ? info : setup.info;
        require(
            farmingSetupInfo.ammPlugin != address(0) &&
            farmingSetupInfo.liquidityPoolTokenAddress != address(0) &&
            farmingSetupInfo.originalRewardPerBlock > 0 &&
            (farmingSetupInfo.free || farmingSetupInfo.maxStakeable > 0),
            "Invalid setup configuration"
        );
        if(add || !disable) {
            farmingSetupInfo.renewTimes = farmingSetupInfo.renewTimes + 1;
            if(farmingSetupInfo.renewTimes == 0) {
                farmingSetupInfo.renewTimes = farmingSetupInfo.renewTimes - 1;
            }
        }

        if (add) {
            address mainTokenAddress = farmingSetupInfo.mainTokenAddress;
            address ammPlugin = farmingSetupInfo.ammPlugin;
            (,,address[] memory tokenAddresses) = IAMM(ammPlugin).byLiquidityPool(farmingSetupInfo.liquidityPoolTokenAddress);
            farmingSetupInfo.ethereumAddress = address(0);
            if (farmingSetupInfo.involvingETH) {
                (farmingSetupInfo.ethereumAddress,,) = IAMM(ammPlugin).data();
            }
            bool mainTokenFound = false;
            bool ethTokenFound = false;
            for(uint256 z = 0; z < tokenAddresses.length; z++) {
                if(tokenAddresses[z] == mainTokenAddress) {
                    mainTokenFound = true;
                } else {
                    emit SetupToken(mainTokenAddress, tokenAddresses[z]);
                    if(tokenAddresses[z] == farmingSetupInfo.ethereumAddress) {
                        ethTokenFound = true;
                    }
                }
            }
            require(mainTokenFound, "No main token");
            require(!farmingSetupInfo.involvingETH || ethTokenFound, "No ETH token");
            _setups[_farmingSetupsCount] = FarmingSetup(farmingSetupInfo, false, 0, 0, 0, 0, farmingSetupInfo.originalRewardPerBlock, 0);
            _toggleSetup(_farmingSetupsCount);
            _farmingSetupsCount += 1;
            return;
        }

        if(disable) {
            require(setup.active, "Not possible");
            _toggleSetup(setupIndex);
            return;
        }

        if (setup.active && setup.info.free && setup.endBlock < block.number) {
            setup = _setups[setupIndex];
            uint256 difference = info.originalRewardPerBlock < farmingSetupInfo.originalRewardPerBlock ? farmingSetupInfo.originalRewardPerBlock - info.originalRewardPerBlock : info.originalRewardPerBlock - farmingSetupInfo.originalRewardPerBlock;
            uint256 duration = setup.endBlock - block.number;
            uint256 amount = difference * duration;
            if (amount > 0) {
                if (info.originalRewardPerBlock < farmingSetupInfo.originalRewardPerBlock) {
                    _giveBack(amount);
                } else {
                    require(_ensureTransfer(amount), "Insufficient reward in extension.");
                }
                _updateFreeSetup(setupIndex, 0, 0, difference, info.originalRewardPerBlock < farmingSetupInfo.originalRewardPerBlock);
            }
        }
        farmingSetupInfo.originalRewardPerBlock = info.originalRewardPerBlock;
        setup.info = farmingSetupInfo;
    }


    function _transferToMeAndCheckAllowance(FarmingSetup memory setup, FarmingPositionRequest memory request) private returns(IAMM amm, uint256 liquidityPoolAmount, uint256 mainTokenAmount) {
        require(request.amount > 0, "No amount");
        // retrieve the values
        amm = IAMM(setup.info.ammPlugin);
        require(request.amount >= setup.info.minStakeable, "Invalid liquidity.");
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

    function _addLiquidity(uint256 setupIndex, FarmingPositionRequest memory request) private returns(LiquidityPoolData memory liquidityPoolData) {
        (IAMM amm, uint256 liquidityPoolAmount, uint256 mainTokenAmount) = _transferToMeAndCheckAllowance(_setups[setupIndex], request);
        // liquidity pool data struct for the AMM
        liquidityPoolData = LiquidityPoolData(
            _setups[setupIndex].info.liquidityPoolTokenAddress,
            request.amountIsLiquidityPool ? liquidityPoolAmount : mainTokenAmount,
            _setups[setupIndex].info.mainTokenAddress,
            request.amountIsLiquidityPool,
            _setups[setupIndex].info.involvingETH,
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
    }

    /** @dev helper function used to remove liquidity from a free position or to burn item farm tokens and retrieve their content.
      * @param positionId id of the position.
      * @param setupIndex index of the setup related to the item farm tokens.
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
        FarmingPosition storage farmingPosition = _positions[positionId];
        // remaining liquidity
        uint256 remainingLiquidity;
        // we are removing liquidity using the setup items
        if (_setups[farmingPosition.setupIndex].info.free && farmingPosition.creationBlock != 0 && positionId != 0) {
            // update the remaining liquidity
            remainingLiquidity = farmingPosition.liquidityPoolTokenAmount - removedLiquidity;
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
        if (!_setups[setupIndex].info.free && _setups[setupIndex].active && !isUnlock) {
            _toggleSetup(setupIndex);
        } else if (_setups[farmingPosition.setupIndex].info.free && positionId != 0) {
            // delete the farming position after the withdraw
            if (remainingLiquidity == 0) {
                delete _positions[positionId];
            } else {
                // update the creation block and amount
                farmingPosition.liquidityPoolTokenAmount = remainingLiquidity;
            }
            // check if setup is marked as finished or not
            if (_setups[farmingPosition.setupIndex].active && _setups[farmingPosition.setupIndex].endBlock <= block.number) {
                _toggleSetup(farmingPosition.setupIndex);
            }
        }
    }

    /** @dev updates the free setup with the given index.
      * @param setupIndex index of the setup that we're updating.
      * @param amount amount of liquidity that we're adding/removeing.
      * @param positionId 
     */
    function _updateFreeSetup(uint256 setupIndex, uint256 amount, uint256 positionId, bool fromExit) private {
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
    }

    function _toggleSetup(uint256 setupIndex) private {
        FarmingSetup storage setup = _setups[setupIndex];
        require(!setup.active || block.number >= setup.endBlock, "Not valid activation");

        if (setup.active && block.number >= setup.endBlock && setup.info.renewTimes == 0) {
            setup.active = false;
            return;
        } else if (block.number < setup.endBlock && setup.info.free) {
            setup.active = false;
            setup.endBlock = block.number;
            setup.info.renewTimes = 0;
            _giveBack((setup.endBlock - block.number) * setup.rewardPerBlock);
            _updateFreeSetup(setupIndex, 0, 0, false);
            return;
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
                return;
            }
        }

        setup.active = _ensureTransfer(setup.rewardPerBlock * setup.info.blockDuration);

        if (setup.active) {
            // set new setup
            _setups[_farmingSetupsCount] = setup;
            // update old setup
            setup.active = false;
            setup.info.renewTimes = 0;
            // update new setup
            _setups[_farmingSetupsCount].info.renewTimes -= 1;
            _setups[_farmingSetupsCount].startBlock = block.number;
            _setups[_farmingSetupsCount].endBlock = _setups[_farmingSetupsCount].startBlock + _setups[_farmingSetupsCount].info.blockDuration;
            _setups[_farmingSetupsCount].totalSupply = 0;
            // update farming setups count
            _farmingSetupsCount += 1;
        } else {
            setup.info.renewTimes = 0;
        }
    }

    /** @dev mints a new FarmToken inside the collection for the given position.
      * @param uniqueOwner farming position owner.
      * @param amount amount of to mint for a farm token.
      * @param setupIndex index of the setup.
      * @return objectId new farm token object id.
     */
    function _mintFarmTokenAmount(address uniqueOwner, uint256 amount, uint256 setupIndex) private returns(uint256 objectId) {
        if (_setups[setupIndex].objectId == 0) {
            (objectId,) = INativeV1(_farmTokenCollection).mint(amount, string(abi.encodePacked("Farming LP ", _toString(_setups[setupIndex].info.liquidityPoolTokenAddress))), "fLP", IFarmFactory(_factory).getFarmTokenURI(), true);
            emit FarmToken(objectId, _setups[setupIndex].info.liquidityPoolTokenAddress, setupIndex, _setups[setupIndex].endBlock);
            _objectIdSetup[objectId] = setupIndex;
            _setups[setupIndex].objectId = objectId;
        } else {
            INativeV1(_farmTokenCollection).mint(_setups[setupIndex].objectId, amount);
        }
        INativeV1(_farmTokenCollection).safeTransferFrom(address(this), uniqueOwner, _setups[setupIndex].objectId, amount, "");
    }

    /** @dev burns a farm token from the collection.
      * @param objectId object id where to burn liquidity.
      * @param amount amount of liquidity to burn.
      */
    function _burnFarmTokenAmount(uint256 objectId, uint256 amount) private {
        INativeV1 tokenCollection = INativeV1(_farmTokenCollection);
        // transfer the liquidity mining farm token to this contract
        tokenCollection.safeTransferFrom(msg.sender, address(this), objectId, amount, "");
        // burn the liquidity mining farm token
        tokenCollection.burn(objectId, amount);
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

    /** @dev gives back the reward to the extension.
      * @param amount to give back.
     */
    function _giveBack(uint256 amount) private {
        if(amount == 0) {
            return;
        }
        if (_rewardTokenAddress == address(0)) {
            IFarmExtension(_extension).backToYou{value : amount}(amount);
        } else {
            IERC20(_rewardTokenAddress).approve(_extension, amount);
            IFarmExtension(_extension).backToYou(amount);
        }
    }

    /** @dev ensures the transfer from the contract to the extension.
      * @param amount amount to transfer.
     */
    function _ensureTransfer(uint256 amount) private returns(bool) {
        uint256 initialBalance = _rewardTokenAddress == address(0) ? address(this).balance : IERC20(_rewardTokenAddress).balanceOf(address(this));
        uint256 expectedBalance = initialBalance + amount;
        try IFarmExtension(_extension).transferTo(amount) {} catch {}
        uint256 actualBalance = _rewardTokenAddress == address(0) ? address(this).balance : IERC20(_rewardTokenAddress).balanceOf(address(this));
        if(actualBalance == expectedBalance) {
            return true;
        }
        _giveBack(actualBalance - initialBalance);
        return false;
    }
}