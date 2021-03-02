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

contract FarmMain is IFarmMain, ERC1155Receiver {

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
    // mapping containing all the currently available farming setups info
    mapping(uint256 => FarmingSetupInfo) public _setupsInfo;
    // counter for the farming setup info
    uint256 public _farmingSetupsInfoCount;
    // mapping containing all the currently available farming setups
    mapping(uint256 => FarmingSetup) private _setups;
    // counter for the farming setups
    uint256 public _farmingSetupsCount;
    // mapping containing all the positions
    mapping(uint256 => FarmingPosition) private _positions;
    // mapping containing the reward per token per setup per block
    mapping(uint256 => uint256) private _rewardPerTokenPerSetup;
    // mapping containing the reward per token paid per position
    mapping(uint256 => uint256) private _rewardPerTokenPaid;
    // mapping containing whether a liquidity mining position has been partially reedemed or not
    mapping(uint256 => uint256) private _partiallyRedeemed;
    // mapping containing object id to setup index
    mapping(uint256 => uint256) private _objectIdSetup;
    // mapping containing all the number of opened positions for each setups
    mapping(uint256 => uint256) public _setupPositionsCount;
    // mapping containing all the reward received/paid per setup
    mapping(uint256 => uint256) public _rewardReceived;
    mapping(uint256 => uint256) public _rewardPaid;

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
        require(_setups[setupIndex].startBlock <= block.number && _setups[setupIndex].endBlock > block.number, "Invalid setup");
        _;
    }

    receive() external payable {}

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
      * @return farming position with the given id.
     */
    function position(uint256 positionId) public view returns (FarmingPosition memory) {
        return _positions[positionId];
    }

    function setups() public view returns (FarmingSetup[] memory) {
        FarmingSetup[] memory farmingSetups = new FarmingSetup[](_farmingSetupsCount);
        for (uint256 i = 0; i < _farmingSetupsCount; i++) {
            farmingSetups[i] = _setups[i];
        }
        return farmingSetups;
    }

    function activateSetup(uint256 setupInfoIndex) public {
        require(_setupsInfo[setupInfoIndex].renewTimes > 0 && !_setups[_setupsInfo[setupInfoIndex].lastSetupIndex].active, "Invalid toggle.");
        _toggleSetup(_setupsInfo[setupInfoIndex].lastSetupIndex);
    }

    function openPosition(FarmingPositionRequest memory request) public payable activeExtensionOnly activeSetupOnly(request.setupIndex) returns(uint256 positionId) {
        // retrieve the setup
        FarmingSetup storage chosenSetup = _setups[request.setupIndex];
        // retrieve the unique owner
        address uniqueOwner = (request.positionOwner != address(0)) ? request.positionOwner : msg.sender;
        // create the position id
        positionId = uint256(keccak256(abi.encode(uniqueOwner, request.setupIndex)));
        // create the lp data for the amm
        (LiquidityPoolData memory liquidityPoolData, uint256 mainTokenAmount) = _addLiquidity(request.setupIndex, request);
        // calculate the reward
        uint256 reward;
        uint256 lockedRewardPerBlock;
        if (!_setupsInfo[chosenSetup.infoIndex].free) {
            (reward, lockedRewardPerBlock) = calculateLockedFarmingReward(request.setupIndex, mainTokenAmount, false, 0);
            require(reward > 0 && lockedRewardPerBlock > 0, "Insufficient staked amount");
            chosenSetup.totalSupply = chosenSetup.totalSupply + mainTokenAmount;
            chosenSetup.lastUpdateBlock = block.number;
            _mintFarmTokenAmount(uniqueOwner, liquidityPoolData.amount, request.setupIndex);
        } else {
            _updateFreeSetup(request.setupIndex, liquidityPoolData.amount, positionId, false);
        }
        _positions[positionId] = FarmingPosition({
            uniqueOwner: uniqueOwner,
            setupIndex : request.setupIndex,
            liquidityPoolTokenAmount: liquidityPoolData.amount,
            mainTokenAmount: mainTokenAmount,
            reward: reward,
            lockedRewardPerBlock: lockedRewardPerBlock,
            creationBlock: block.number
        });
        _setupPositionsCount[request.setupIndex] += _setupsInfo[chosenSetup.infoIndex].free ? 1 : 2;
        emit Transfer(positionId, address(0), uniqueOwner);
    }

    function addLiquidity(uint256 positionId, FarmingPositionRequest memory request) public payable activeExtensionOnly activeSetupOnly(request.setupIndex) byPositionOwner(positionId) {
        // retrieve farming position
        FarmingPosition storage farmingPosition = _positions[positionId];
        FarmingSetup storage chosenSetup = _setups[farmingPosition.setupIndex];
        // check if farmoing position is valid
        require(_setupsInfo[chosenSetup.infoIndex].free, "Invalid add liquidity");
        // create the lp data for the amm
        (LiquidityPoolData memory liquidityPoolData,) = _addLiquidity(farmingPosition.setupIndex, request);
        // rebalance the reward per token
        _rewardPerTokenPerSetup[farmingPosition.setupIndex] += (((block.number - chosenSetup.lastUpdateBlock) * chosenSetup.rewardPerBlock) * 1e18) / chosenSetup.totalSupply;
        farmingPosition.reward = calculateFreeFarmingReward(positionId);
        _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[farmingPosition.setupIndex];
        farmingPosition.liquidityPoolTokenAmount += liquidityPoolData.amount;
        // update the last block update variablex
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
        uint256 currentBlock = block.number;
        if (!_setupsInfo[_setups[farmingPosition.setupIndex].infoIndex].free) {
            // check if reward is available
            require(farmingPosition.reward > 0, "No reward");
            // check if it's a partial reward or not
            if (_setups[farmingPosition.setupIndex].endBlock > block.number) {
                // calculate the reward from the farming position creation block to the current block multiplied by the reward per block
                (reward,) = calculateLockedFarmingReward(0, 0, true, positionId);
            }
            require(reward <= farmingPosition.reward, "Reward is bigger than expected");
            // remove the partial reward from the liquidity mining position total reward
            farmingPosition.reward = farmingPosition.reward - reward;
        } else {
            // rebalance setup
            currentBlock = currentBlock > _setups[farmingPosition.setupIndex].endBlock ? _setups[farmingPosition.setupIndex].endBlock : currentBlock;
            _rewardPerTokenPerSetup[farmingPosition.setupIndex] += (((currentBlock - _setups[farmingPosition.setupIndex].lastUpdateBlock) * _setups[farmingPosition.setupIndex].rewardPerBlock) * 1e18) / _setups[farmingPosition.setupIndex].totalSupply;
            reward = calculateFreeFarmingReward(positionId);
            _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[farmingPosition.setupIndex];
            farmingPosition.reward = 0;
            // update the last block update variable
            _setups[farmingPosition.setupIndex].lastUpdateBlock = currentBlock;   
        }
        if (reward > 0) {
            // transfer the reward
            if (_rewardTokenAddress != address(0)) {
                _safeTransfer(_rewardTokenAddress, farmingPosition.uniqueOwner, reward);
            } else {
                (bool result,) = farmingPosition.uniqueOwner.call{value:reward}("");
                require(result, "Invalid ETH transfer.");
            }
            _rewardPaid[farmingPosition.setupIndex] += reward;
        }
        if (_setups[farmingPosition.setupIndex].endBlock <= block.number) {
            if (_setups[farmingPosition.setupIndex].active) {
                _toggleSetup(farmingPosition.setupIndex);
            }
            // close the locked position after withdrawing all the reward
            if (!_setupsInfo[_setups[farmingPosition.setupIndex].infoIndex].free) {
                _setupPositionsCount[farmingPosition.setupIndex] -= 1;
                if (_setupPositionsCount[farmingPosition.setupIndex] == 0 && !_setups[farmingPosition.setupIndex].active) {
                    _giveBack(_rewardReceived[farmingPosition.setupIndex] - _rewardPaid[farmingPosition.setupIndex]);
                    delete _setups[farmingPosition.setupIndex];
                }
                delete _positions[positionId];
            }
        } else if (!_setupsInfo[_setups[farmingPosition.setupIndex].infoIndex].free) {
            // set the partially redeemed amount
            _partiallyRedeemed[positionId] += reward;
        }
    }

    function withdrawLiquidity(uint256 positionId, uint256 objectId, bool unwrapPair, uint256 removedLiquidity) public {
        // retrieve farming position
        FarmingPosition memory farmingPosition = _positions[positionId];
        uint256 setupIndex = farmingPosition.setupIndex;
        if (objectId != 0 && address(INativeV1(_farmTokenCollection).asInteroperable(objectId)) != address(0)) {
            setupIndex = _objectIdSetup[objectId];
        }
        require((positionId != 0 && objectId == 0) || (objectId != 0 && positionId == 0 && _setups[setupIndex].objectId == objectId), "Invalid position");
        // current owned liquidity
        require(
            (
                _setupsInfo[_setups[farmingPosition.setupIndex].infoIndex].free && 
                farmingPosition.creationBlock != 0 &&
                removedLiquidity <= farmingPosition.liquidityPoolTokenAmount &&
                farmingPosition.uniqueOwner == msg.sender
            ) || INativeV1(_farmTokenCollection).balanceOf(msg.sender, objectId) >= removedLiquidity, "Invalid withdraw");
        // check if liquidity mining position is valid
        require(_setupsInfo[_setups[farmingPosition.setupIndex].infoIndex].free || (_setups[setupIndex].endBlock <= block.number), "Invalid withdraw");
        // burn the liquidity in the locked setup
        if (positionId == 0) {
            _burnFarmTokenAmount(objectId, removedLiquidity);
        } else {
            withdrawReward(positionId);
            _setups[farmingPosition.setupIndex].totalSupply -= removedLiquidity;
        }
        _removeLiquidity(positionId, setupIndex, unwrapPair, removedLiquidity, false);
        if (positionId == 0) {
            _setupPositionsCount[setupIndex] -= 1;
            if (_setupPositionsCount[setupIndex] == 0 && !_setups[setupIndex].active) {
                _giveBack(_rewardReceived[setupIndex] - _rewardPaid[setupIndex]);
                delete _setups[setupIndex];
            }
        }
    }

    function unlock(uint256 positionId, bool unwrapPair) public payable byPositionOwner(positionId) {
        // retrieve liquidity mining position
        FarmingPosition storage farmingPosition = _positions[positionId];
        require(!_setupsInfo[_setups[farmingPosition.setupIndex].infoIndex].free && _setups[farmingPosition.setupIndex].endBlock > block.number, "Invalid unlock");
        uint256 rewardToGiveBack = _partiallyRedeemed[positionId];
        // must pay a penalty fee
        rewardToGiveBack += _setupsInfo[_setups[farmingPosition.setupIndex].infoIndex].penaltyFee == 0 ? 0 : (farmingPosition.reward * ((_setupsInfo[_setups[farmingPosition.setupIndex].infoIndex].penaltyFee * 1e18) / ONE_HUNDRED) / 1e18);
        // add all the unissued reward
        if (rewardToGiveBack > 0) {
            _safeTransferFrom(_rewardTokenAddress, msg.sender, address(this), rewardToGiveBack);
            _giveBack(rewardToGiveBack);
        } 
        _setups[farmingPosition.setupIndex].totalSupply -= farmingPosition.mainTokenAmount;
        _burnFarmTokenAmount(_setups[farmingPosition.setupIndex].objectId, farmingPosition.liquidityPoolTokenAmount);
        _removeLiquidity(positionId, farmingPosition.setupIndex, unwrapPair, farmingPosition.liquidityPoolTokenAmount, true);
        _setupPositionsCount[farmingPosition.setupIndex] -= 2;
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
            require(mainTokenAmount <= _setupsInfo[_setups[setupIndex].infoIndex].maxStakeable - setup.totalSupply, "Invalid liquidity");
            uint256 remainingBlocks = block.number >= setup.endBlock ? 0 : setup.endBlock - block.number;
            // get amount of remaining blocks
            require(remainingBlocks > 0, "FarmingSetup ended");
            // get total reward still available (= 0 if rewardPerBlock = 0)
            require(setup.rewardPerBlock * remainingBlocks > 0, "No rewards");
            // calculate relativeRewardPerBlock
            relativeRewardPerBlock = (setup.rewardPerBlock * ((mainTokenAmount * 1e18) / _setupsInfo[_setups[setupIndex].infoIndex].maxStakeable)) / 1e18;
            // check if rewardPerBlock is greater than 0
            require(relativeRewardPerBlock > 0, "Invalid rpb");
            // calculate reward by multiplying relative reward per block and the remaining blocks
            reward = relativeRewardPerBlock * remainingBlocks;
        }
    }

    function calculateFreeFarmingReward(uint256 positionId) public view returns(uint256 reward) {
        FarmingPosition memory farmingPosition = _positions[positionId];
        reward = ((_rewardPerTokenPerSetup[farmingPosition.setupIndex] - _rewardPerTokenPaid[positionId]) * farmingPosition.liquidityPoolTokenAmount) / 1e18;
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
        FarmingSetupInfo memory farmingSetupInfo = info;

        if(add || !disable) {
            farmingSetupInfo.renewTimes = farmingSetupInfo.renewTimes + 1;
            if(farmingSetupInfo.renewTimes == 0) {
                farmingSetupInfo.renewTimes = farmingSetupInfo.renewTimes - 1;
            }
        }

        if (add) {
            require(
                farmingSetupInfo.ammPlugin != address(0) &&
                farmingSetupInfo.liquidityPoolTokenAddress != address(0) &&
                farmingSetupInfo.originalRewardPerBlock > 0 &&
                (farmingSetupInfo.free || farmingSetupInfo.maxStakeable > 0),
                "Invalid setup configuration"
            );

            (,,address[] memory tokenAddresses) = IAMM(farmingSetupInfo.ammPlugin).byLiquidityPool(farmingSetupInfo.liquidityPoolTokenAddress);
            farmingSetupInfo.ethereumAddress = address(0);
            if (farmingSetupInfo.involvingETH) {
                (farmingSetupInfo.ethereumAddress,,) = IAMM(farmingSetupInfo.ammPlugin).data();
            }
            bool mainTokenFound = false;
            bool ethTokenFound = false;
            for(uint256 z = 0; z < tokenAddresses.length; z++) {
                if(tokenAddresses[z] == farmingSetupInfo.mainTokenAddress) {
                    mainTokenFound = true;
                    if(tokenAddresses[z] == farmingSetupInfo.ethereumAddress) {
                        ethTokenFound = true;
                    }
                } else {
                    emit SetupToken(farmingSetupInfo.mainTokenAddress, tokenAddresses[z]);
                    if(tokenAddresses[z] == farmingSetupInfo.ethereumAddress) {
                        ethTokenFound = true;
                    }
                }
            }
            require(mainTokenFound, "No main token");
            require(!farmingSetupInfo.involvingETH || ethTokenFound, "No ETH token");
            farmingSetupInfo.setupsCount = 0;
            _setupsInfo[_farmingSetupsInfoCount] = farmingSetupInfo;
            _setups[_farmingSetupsCount] = FarmingSetup(_farmingSetupsInfoCount, false, 0, 0, 0, 0, farmingSetupInfo.originalRewardPerBlock, 0);
            _setupsInfo[_farmingSetupsInfoCount].lastSetupIndex = _farmingSetupsCount;
            _farmingSetupsInfoCount += 1;
            _farmingSetupsCount += 1;
            return;
        }

        FarmingSetup storage setup = _setups[setupIndex];
        farmingSetupInfo = _setupsInfo[_setups[setupIndex].infoIndex];

        if(disable) {
            require(setup.active, "Not possible");
            _toggleSetup(setupIndex);
            return;
        }
        
        info.renewTimes -= 1;

        if (setup.active && _setupsInfo[_setups[setupIndex].infoIndex].free) {
            setup = _setups[setupIndex];
            uint256 difference = info.originalRewardPerBlock < farmingSetupInfo.originalRewardPerBlock ? farmingSetupInfo.originalRewardPerBlock - info.originalRewardPerBlock : info.originalRewardPerBlock - farmingSetupInfo.originalRewardPerBlock;
            uint256 duration = setup.endBlock - block.number;
            uint256 amount = difference * duration;
            if (amount > 0) {
                if (info.originalRewardPerBlock < farmingSetupInfo.originalRewardPerBlock) {
                    //_rewardReceived[setupIndex] = (((block.number - setup.startBlock) * farmingSetupInfo.originalRewardPerBlock) + amount) + info.originalRewardPerBlock;
                    _rewardReceived[setupIndex] -= amount;
                    _giveBack(amount);
                } else {
                    require(_ensureTransfer(amount), "Insufficient reward in extension.");
                    _rewardReceived[setupIndex] += amount;
                }
                _updateFreeSetup(setupIndex, 0, 0, false);
                setup.rewardPerBlock = info.originalRewardPerBlock;
            }
            _setupsInfo[_setups[setupIndex].infoIndex].originalRewardPerBlock = info.originalRewardPerBlock;
        }
        _setupsInfo[_setups[setupIndex].infoIndex].renewTimes = info.renewTimes;
    }


    function _transferToMeAndCheckAllowance(FarmingSetup memory setup, FarmingPositionRequest memory request) private returns(IAMM amm, uint256 liquidityPoolAmount, uint256 mainTokenAmount) {
        require(request.amount > 0, "No amount");
        // retrieve the values
        amm = IAMM(_setupsInfo[setup.infoIndex].ammPlugin);
        liquidityPoolAmount = request.amountIsLiquidityPool ? request.amount : 0;
        mainTokenAmount = request.amountIsLiquidityPool ? 0 : request.amount;
        address[] memory tokens;
        uint256[] memory tokenAmounts;
        // if liquidity pool token amount is provided, the position is opened by liquidity pool token amount
        if(request.amountIsLiquidityPool) {
            _safeTransferFrom(_setupsInfo[setup.infoIndex].liquidityPoolTokenAddress, msg.sender, address(this), liquidityPoolAmount);
            (tokenAmounts, tokens) = amm.byLiquidityPoolAmount(_setupsInfo[setup.infoIndex].liquidityPoolTokenAddress, liquidityPoolAmount);
        } else {
            // else it is opened by the tokens amounts
            (liquidityPoolAmount, tokenAmounts, tokens) = amm.byTokenAmount(_setupsInfo[setup.infoIndex].liquidityPoolTokenAddress, _setupsInfo[setup.infoIndex].mainTokenAddress, mainTokenAmount);
        }

        // iterate the tokens and perform the transferFrom and the approve
        for(uint256 i = 0; i < tokens.length; i++) {
            if(tokens[i] == _setupsInfo[setup.infoIndex].mainTokenAddress) {
                mainTokenAmount = tokenAmounts[i];
                require(mainTokenAmount >= _setupsInfo[setup.infoIndex].minStakeable, "Invalid liquidity.");
                if(request.amountIsLiquidityPool) {
                    break;
                }
            }
            if(request.amountIsLiquidityPool) {
                continue;
            }
            if(_setupsInfo[setup.infoIndex].involvingETH && _setupsInfo[setup.infoIndex].ethereumAddress == tokens[i]) {
                require(msg.value == tokenAmounts[i], "Incorrect eth value");
            } else {
                _safeTransferFrom(tokens[i], msg.sender, address(this), tokenAmounts[i]);
                _safeApprove(tokens[i], _setupsInfo[setup.infoIndex].ammPlugin, tokenAmounts[i]);
            }
        }
    }

    function _addLiquidity(uint256 setupIndex, FarmingPositionRequest memory request) private returns(LiquidityPoolData memory liquidityPoolData, uint256 tokenAmount) {
        (IAMM amm, uint256 liquidityPoolAmount, uint256 mainTokenAmount) = _transferToMeAndCheckAllowance(_setups[setupIndex], request);
        // liquidity pool data struct for the AMM
        liquidityPoolData = LiquidityPoolData(
            _setupsInfo[_setups[setupIndex].infoIndex].liquidityPoolTokenAddress,
            request.amountIsLiquidityPool ? liquidityPoolAmount : mainTokenAmount,
            _setupsInfo[_setups[setupIndex].infoIndex].mainTokenAddress,
            request.amountIsLiquidityPool,
            _setupsInfo[_setups[setupIndex].infoIndex].involvingETH,
            address(this)
        );
        tokenAmount = mainTokenAmount;
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
        FarmingSetupInfo memory setupInfo = _setupsInfo[_setups[setupIndex].infoIndex];
        // create liquidity pool data struct for the AMM
        LiquidityPoolData memory lpData = LiquidityPoolData(
            setupInfo.liquidityPoolTokenAddress,
            removedLiquidity,
            setupInfo.mainTokenAddress,
            true,
            setupInfo.involvingETH,
            msg.sender
        );
        // retrieve the position
        FarmingPosition storage farmingPosition = _positions[positionId];
        // remaining liquidity
        uint256 remainingLiquidity;
        // we are removing liquidity using the setup items
        if (setupInfo.free && farmingPosition.creationBlock != 0 && positionId != 0) {
            // update the remaining liquidity
            remainingLiquidity = farmingPosition.liquidityPoolTokenAmount - removedLiquidity;
        }
        // retrieve fee stuff
        (uint256 exitFeePercentage, address exitFeeWallet) = IFarmFactory(_factory).feePercentageInfo();
        // pay the fees!
        if (exitFeePercentage > 0) {
            uint256 fee = (lpData.amount * ((exitFeePercentage * 1e18) / ONE_HUNDRED)) / 1e18;
            _safeTransfer(setupInfo.liquidityPoolTokenAddress, exitFeeWallet, fee);
            lpData.amount = lpData.amount - fee;
        }
        // check if the user wants to unwrap its pair or not
        if (unwrapPair) {
            // remove liquidity using AMM
            _safeApprove(lpData.liquidityPoolAddress, setupInfo.ammPlugin, lpData.amount);
            IAMM(setupInfo.ammPlugin).removeLiquidity(lpData);
        } else {
            // send back the liquidity pool token amount without the fee
            _safeTransfer(lpData.liquidityPoolAddress, lpData.receiver, lpData.amount);
        }
        if (!setupInfo.free && _setups[setupIndex].active && !isUnlock) {
            _toggleSetup(setupIndex);
        } else if (setupInfo.free && positionId != 0) {
            if (_setups[farmingPosition.setupIndex].active && _setups[farmingPosition.setupIndex].endBlock <= block.number) {
                _toggleSetup(farmingPosition.setupIndex);
            }
            // delete the farming position after the withdraw
            if (remainingLiquidity == 0) {
                _setupPositionsCount[farmingPosition.setupIndex] -= 1;
                if (_setupPositionsCount[farmingPosition.setupIndex] == 0 && !_setups[farmingPosition.setupIndex].active) {
                    _giveBack(_rewardReceived[farmingPosition.setupIndex] - _rewardPaid[farmingPosition.setupIndex]);
                    delete _setups[farmingPosition.setupIndex];
                }
                delete _positions[positionId];
            } else {
                // update the creation block and amount
                farmingPosition.liquidityPoolTokenAmount = remainingLiquidity;
            }
        }
    }

    /** @dev updates the free setup with the given index.
      * @param setupIndex index of the setup that we're updating.
      * @param amount amount of liquidity that we're adding/removeing.
      * @param positionId position id.
      * @param fromExit if it's from an exit or not.
     */
    function _updateFreeSetup(uint256 setupIndex, uint256 amount, uint256 positionId, bool fromExit) private {
        uint256 currentBlock = block.number < _setups[setupIndex].endBlock ? block.number : _setups[setupIndex].endBlock;
        if (_setups[setupIndex].totalSupply != 0) {
            uint256 lastUpdateBlock = _setups[setupIndex].lastUpdateBlock < _setups[setupIndex].startBlock ? _setups[setupIndex].startBlock : _setups[setupIndex].lastUpdateBlock;
            _rewardPerTokenPerSetup[setupIndex] += (((currentBlock - lastUpdateBlock) * _setups[setupIndex].rewardPerBlock) * 1e18) / _setups[setupIndex].totalSupply;
        }
        // update the last block update variable
        _setups[setupIndex].lastUpdateBlock = currentBlock;
        if (positionId != 0) {
            _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[setupIndex];
        }
        if (amount > 0) {
            fromExit ? _setups[setupIndex].totalSupply -= amount : _setups[setupIndex].totalSupply += amount;
        }
    }

    function _toggleSetup(uint256 setupIndex) private {
        FarmingSetup storage setup = _setups[setupIndex];
        // require(!setup.active || block.number >= setup.endBlock, "Not valid activation");

        if (setup.active && block.number >= setup.endBlock && _setupsInfo[setup.infoIndex].renewTimes == 0) {
            setup.active = false;
            return;
        } else if (block.number > setup.startBlock && block.number <= setup.endBlock && setup.active) {
            setup.active = false;
            _setupsInfo[setup.infoIndex].renewTimes = 0;
            uint256 amount;
            if (_setupsInfo[setup.infoIndex].free) {
                amount = (setup.endBlock - block.number) * setup.rewardPerBlock;
                setup.endBlock = block.number;
                _updateFreeSetup(setupIndex, 0, 0, false);
            } else {
                uint256 unissuedRpb = setup.rewardPerBlock - ((setup.rewardPerBlock * (setup.totalSupply * 1e18 / _setupsInfo[setup.infoIndex].maxStakeable)) / 1e18);
                amount = ((setup.endBlock - block.number) * unissuedRpb);
                setup.endBlock = block.number;
            }
            _rewardReceived[setupIndex] -= amount;
            _giveBack(amount);
            return;
        }

        // TODO: check if still needed
        if (!_setupsInfo[setup.infoIndex].free) {
            // count the number of currently active locked setups
            uint256 count = 0;
            for(uint256 i = 0; i < _farmingSetupsCount; i++) {
                if(_setupsInfo[_setups[i].infoIndex].free || i == setupIndex) continue;
                if(_setups[i].active) {
                    // increase the counter
                    count++;
                }
            }
            // set the setup as not renewable
            if(count > MAX_CONTEMPORARY_LOCKED) {
                _setupsInfo[setup.infoIndex].renewTimes = 0;
                return;
            }
        }

        bool wasActive = setup.active;
        setup.active = _ensureTransfer(setup.rewardPerBlock * _setupsInfo[setup.infoIndex].blockDuration);

        if (setup.active && wasActive) {
            _rewardReceived[_farmingSetupsCount] = setup.rewardPerBlock * _setupsInfo[setup.infoIndex].blockDuration;
            // set new setup
            _setups[_farmingSetupsCount] = abi.decode(abi.encode(setup), (FarmingSetup));
            // update old setup
            _setups[setupIndex].active = false;
            // update new setup
            _setupsInfo[setup.infoIndex].renewTimes -= 1;
            _setupsInfo[setup.infoIndex].setupsCount += 1;
            _setupsInfo[setup.infoIndex].lastSetupIndex = _farmingSetupsCount;
            _setups[_farmingSetupsCount].startBlock = block.number;
            _setups[_farmingSetupsCount].endBlock = block.number + _setupsInfo[_setups[_farmingSetupsCount].infoIndex].blockDuration;
            _setups[_farmingSetupsCount].objectId = 0;
            _setups[_farmingSetupsCount].totalSupply = 0;
            _farmingSetupsCount += 1;
        } else if (setup.active && !wasActive) {
            _rewardReceived[setupIndex] = setup.rewardPerBlock * _setupsInfo[_setups[setupIndex].infoIndex].blockDuration;
            // update new setup
            _setups[setupIndex].startBlock = block.number;
            _setups[setupIndex].endBlock = block.number + _setupsInfo[_setups[setupIndex].infoIndex].blockDuration;
            _setups[setupIndex].totalSupply = 0;
            _setupsInfo[_setups[setupIndex].infoIndex].renewTimes -= 1;
        } else if (!wasActive) {
            _setupsInfo[_setups[setupIndex].infoIndex].renewTimes = 0;
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
            (objectId,) = INativeV1(_farmTokenCollection).mint(amount, string(abi.encodePacked("Farming LP ", _toString(_setupsInfo[_setups[setupIndex].infoIndex].liquidityPoolTokenAddress))), "fLP", IFarmFactory(_factory).getFarmTokenURI(), true);
            emit FarmToken(objectId, _setupsInfo[_setups[setupIndex].infoIndex].liquidityPoolTokenAddress, setupIndex, _setups[setupIndex].endBlock);
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