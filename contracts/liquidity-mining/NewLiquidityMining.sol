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

    uint256 public constant ONE_HUNDRED = 1e18;
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
    mapping(uint256 => LiquidityMiningSetup) private _setups;
    // total number of setups
    uint256 public _setupsCount;
    // mapping containing all the positions
    mapping(uint256 => LiquidityMiningPosition) public _positions;
    // mapping containing the reward per token per setup per block
    mapping(uint256 => mapping(uint256 => uint256)) public _rewardPerTokenPerSetupPerBlock;
    // mapping containing all the blocks where an update has been triggered
    mapping(uint256 => uint256[]) public _setupUpdateBlocks;
    // mapping containing whether a liquidity mining position has been partially reedemed or not
    mapping(uint256 => uint256) public _partiallyRedeemed;
    // mapping containing whether a locked setup has ended or not and has been used for the rebalance
    mapping(uint256 => bool) public _finishedLockedSetups;
    // mapping containing object id to setup index
    mapping(uint256 => uint256) private _objectIdSetup;
    // load balancer
    LiquidityMiningLoadBalancer public loadBalancer;

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

    /** Public extension methods. */

    /** @dev initializes the liquidity mining contract.
      * @param extension extension address.
      * @param extensionInitData lm extension init payload.
      * @param orchestrator address of the eth item orchestrator.
      * @param rewardTokenAddress address of the reward token.
      * @param liquidityMiningSetupsBytes array containing all the liquidity mining setups as bytes.
      * @param setPinned true if we're setting a pinned setup during initialization, false otherwise.
      * @param pinnedIndex index of the pinned setup.
      * @return extensionReturnCall result of the extension initialization function, if it was called.  
     */
    function init(address extension, bytes memory extensionInitData, address orchestrator, address rewardTokenAddress, bytes memory liquidityMiningSetupsBytes, bool setPinned, uint256 pinnedIndex) public returns(bytes memory extensionReturnCall) {
        require(_factory == address(0), "Already initialized");
        require((_extension = extension) != address(0), "extension");
        _factory = msg.sender;
        emit RewardToken(_rewardTokenAddress = rewardTokenAddress);
        if (keccak256(extensionInitData) != keccak256("")) {
            extensionReturnCall = _call(_extension, extensionInitData);
        }
        (_liquidityFarmTokenCollection,) = IEthItemOrchestrator(orchestrator).createNative(abi.encodeWithSignature("init(string,string,bool,string,address,bytes)", "Covenants Farming", "cFARM", true, ILiquidityMiningFactory(_factory).getLiquidityFarmTokenCollectionURI(), address(this), ""), "");
        _initLiquidityMiningSetups(liquidityMiningSetupsBytes, setPinned, pinnedIndex);
    }

    /** @dev returns the liquidity mining setups.
      * @return array containing all the liquidity mining setups.
     */
    function setups() view public override returns (LiquidityMiningSetup[] memory) {
        LiquidityMiningSetup[] memory setupsArray = new LiquidityMiningSetup[](_setupsCount);
        for (uint256 i = 0; i < _setupsCount - 1; i++) {
            setupsArray[i] = _setups[i];
        }
        return setupsArray;
    }

    /** @dev returns the liquidity mining position associated with the input id.
      * @param id liquidity mining position id.
      * @return liquidity mining position stored at the given id.
     */
    function position(uint256 id) public view returns(LiquidityMiningPosition memory) {
        return _positions[id];
    }

    /** @dev returns the setup index for the given objectId.
      * @param objectId farm token object id.
      * @return setupIndex index of the setup.
     */
    function getObjectIdSetupIndex(uint256 objectId) public view returns (uint256 setupIndex) {
        require(address(INativeV1(_liquidityFarmTokenCollection).asInteroperable(objectId)) != address(0), "Invalid objectId");
        setupIndex = _objectIdSetup[objectId];
    }

    /** @dev this function allows any user to rebalance the pinned setup. */
    function rebalancePinnedSetup() public {
        // TODO
    }

    /** @dev allows the extension to set the liquidity mining setups.
      * @param liquidityMiningSetups liquidity mining setups to set.
      * @param setPinned if we're updating the pinned setup or not.
      * @param pinnedIndex new pinned setup index.
      */
    function setLiquidityMiningSetups(LiquidityMiningSetupConfiguration[] memory liquidityMiningSetups, bool clearPinned, bool setPinned, uint256 pinnedIndex) public override byExtension {
        for (uint256 i = 0; i < liquidityMiningSetups.length; i++) {
            _setOrAddLiquidityMiningSetup(liquidityMiningSetups[i].data, liquidityMiningSetups[i].add, liquidityMiningSetups[i].index);
        }
        _pinnedSetup(clearPinned, setPinned, pinnedIndex);
        // rebalance the pinned setup
        rebalancePinnedSetup();
    }

    /** @dev method used to activate or deactivate the setups.
      * @param setupIndexes array of setup indexes.
      * @param statuses array containing uint256 for each given setup index: if 1 is given, we're activating the setup, otherwise we're deactivating it.
     */
    function toggleSetups(uint256[] memory setupIndexes, uint256[] memory statuses) public virtual override byExtension {
        for (uint256 i = 0; i < setupIndexes.length; i++) {
            _toggleSetup(setupIndexes[i], statuses[i]);
        }
    }

    /** @dev function called by external users to open a new liquidity mining position.
      * @param request Liquidity Mining input data.
    */
    function openPosition(LiquidityMiningPositionRequest memory request) public payable activeExtensionOnly activeSetupOnly(request.setupIndex) returns(uint256 positionId) {
        // TODO 
    }

    /** @dev adds liquidity to the liquidity mining position at the given positionId using the given lpData.
      * @param positionId id of the liquidity mining position.
      * @param request update position request.
      */
    function addLiquidity(uint256 positionId, LiquidityMiningPositionRequest memory request) public payable activeExtensionOnly activeSetupOnly(request.setupIndex) byPositionOwner(positionId) {
        // retrieve liquidity mining position
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionId];
        LiquidityMiningSetup memory chosenSetup = _setups[liquidityMiningPosition.setupIndex];
        // check if liquidity mining position is valid
        require(chosenSetup.free, "Invalid add liquidity");
        (IAMM amm, uint256 liquidityPoolAmount, uint256 mainTokenAmount, bool involvingETH) = _transferToMeAndCheckAllowance(chosenSetup, request);
        // liquidity pool data struct for the AMM
        LiquidityPoolData memory liquidityPoolData = LiquidityPoolData(
            chosenSetup.liquidityPoolTokenAddress,
            request.amountIsLiquidityPool ? liquidityPoolAmount : mainTokenAmount,
            chosenSetup.mainTokenAddress,
            request.amountIsLiquidityPool,
            involvingETH,
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
        _calculateRewardPerToken(liquidityMiningPosition.setupIndex, 0, false);
        // calculate reward before adding liquidity pool data to the position
        uint256 newReward = calculateFreeLiquidityMiningSetupReward(positionId, false);
        // update the liquidity pool token amount
        liquidityMiningPosition.liquidityPoolTokenAmount += liquidityPoolData.amount;
        if (newReward > 0) {
            // transfer the reward
            _rewardTokenAddress != address(0) ? _safeTransfer(_rewardTokenAddress, liquidityMiningPosition.uniqueOwner, newReward) : payable(liquidityMiningPosition.uniqueOwner).transfer(newReward);
        }
        // update the creation block to avoid blocks before the new add liquidity
        liquidityMiningPosition.creationBlock = block.number;
        // rebalance the reward per token
        _calculateRewardPerToken(liquidityMiningPosition.setupIndex, liquidityPoolData.amount, false);
    }

    /** @dev this function allows a user to withdraw the reward.
      * @param positionId liquidity mining position id.
     */
    function withdrawReward(uint256 positionId) public byPositionOwner(positionId) {
        // TODO
    }

    /** @dev allows the withdrawal of the liquidity from a position or from the item tokens.
      * @param positionId id of the position.
      * @param objectId object id of the item token to burn.
      * @param unwrapPair if the liquidity pool tokens will be unwrapped or not.
      * @param removedLiquidity amount of liquidity to remove.
     */
    function withdrawLiquidity(uint256 positionId, uint256 objectId, bool unwrapPair, uint256 removedLiquidity) public {
        // TODO
    }

    /** @dev this function allows a extension to unlock its locked liquidity mining position receiving back its tokens or the lpt amount.
      * @param positionId liquidity mining position id.
      * @param unwrapPair if the caller wants to unwrap his pair from the liquidity pool token or not.
    */
    function unlock(uint256 positionId, bool unwrapPair) public payable byPositionOwner(positionId) {
        // TODO
    }

    /** @dev this function allows a wallet to update the extension of the given liquidity mining position.
      * @param to address of the new extension.
      * @param positionId id of the liquidity mining position.
     */
    function transfer(address to, uint256 positionId) public byPositionOwner(positionId) {
        // retrieve liquidity mining position
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionId];
        require(
            to != address(0) &&
            liquidityMiningPosition.creationBlock != 0,
            "Invalid position"
        );
        liquidityMiningPosition.uniqueOwner = to;
        emit Transfer(positionId, msg.sender, to);
    }

    /** @dev function used to calculate the reward in a locked liquidity mining setup.
      * @param setupIndex liquidity mining setup index.
      * @param mainTokenAmount amount of main token.
      * @param isPartial if we're calculating a partial reward.
      * @param positionId id of the position (used for the partial reward).
      * @return reward total reward for the liquidity mining position extension.
      * @return relativeRewardPerBlock returned for the pinned free setup balancing.
     */
    function calculateLockedLiquidityMiningSetupReward(uint256 setupIndex, uint256 mainTokenAmount, bool isPartial, uint256 positionId) public view returns(uint256 reward, uint256 relativeRewardPerBlock) {
        if (isPartial) {
            // retrieve the position
            LiquidityMiningPosition memory liquidityMiningPosition = _positions[positionId];
            // calculate the reward
            reward = (block.number >= _setups[liquidityMiningPosition.setupIndex].endBlock) ? liquidityMiningPosition.reward : ((block.number - liquidityMiningPosition.creationBlock) * liquidityMiningPosition.lockedRewardPerBlock);
        } else {
            LiquidityMiningSetup memory setup = _setups[setupIndex];
            // check if main token amount is less than the stakeable liquidity
            require(mainTokenAmount <= setup.maxStakeable - setup.currentlyStaked, "Invalid liquidity");
            uint256 remainingBlocks = block.number > setup.endBlock ? 0 : setup.endBlock - block.number;
            // get amount of remaining blocks
            require(remainingBlocks > 0, "Setup ended");
            // get total reward still available (= 0 if rewardPerBlock = 0)
            require(setup.rewardPerBlock * remainingBlocks > 0, "No rewards");
            // calculate relativeRewardPerBlock
            relativeRewardPerBlock = (setup.rewardPerBlock * ((mainTokenAmount * 1e18) / setup.maxStakeable)) / 1e18;
            // check if rewardPerBlock is greater than 0
            require(relativeRewardPerBlock > 0, "Invalid rpb");
            // calculate reward by multiplying relative reward per block and the remaining blocks
            reward = relativeRewardPerBlock * remainingBlocks;
        }
    }

    /** @dev function used to calculate the reward in a free liquidity mining setup.
      * @param positionId liquidity mining position id.
      * @return reward total reward for the liquidity mining position extension.
     */
    function calculateFreeLiquidityMiningSetupReward(uint256 positionId, bool isExt) public view returns(uint256 reward) {
        LiquidityMiningPosition memory liquidityMiningPosition = _positions[positionId];
        for (uint256 i = 0; i < _setupUpdateBlocks[liquidityMiningPosition.setupIndex].length; i++) {
            if (_setupUpdateBlocks[liquidityMiningPosition.setupIndex][i] > _setups[liquidityMiningPosition.setupIndex].endBlock) break;
            if (liquidityMiningPosition.creationBlock < _setupUpdateBlocks[liquidityMiningPosition.setupIndex][i]) {
                reward += (_rewardPerTokenPerSetupPerBlock[liquidityMiningPosition.setupIndex][_setupUpdateBlocks[liquidityMiningPosition.setupIndex][i]] * liquidityMiningPosition.liquidityPoolTokenAmount) / 1e18;
            }
        }
        if (isExt && _setups[liquidityMiningPosition.setupIndex].endBlock > block.number) {
            uint256 rpt = (((block.number - _setups[liquidityMiningPosition.setupIndex].lastBlockUpdate + 1) * _setups[liquidityMiningPosition.setupIndex].rewardPerBlock) * 1e18) / _setups[liquidityMiningPosition.setupIndex].totalSupply;
            reward += (rpt * liquidityMiningPosition.liquidityPoolTokenAmount) / 1e18;
        }
    }

    /** @dev function used to receive batch of erc1155 tokens. */
    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public view override returns(bytes4) {
        require(_liquidityFarmTokenCollection == msg.sender, "Invalid sender");
        return this.onERC1155BatchReceived.selector;
    }

    /** @dev function used to receive erc1155 tokens. */
    function onERC1155Received(address, address, uint256, uint256, bytes memory) public view override returns(bytes4) {
        require(_liquidityFarmTokenCollection == msg.sender, "Invalid sender");
        return this.onERC1155Received.selector;
    }

    /** Private methods. */

    /** @dev initializes the liquidity mining setups during the contract initialization.
      * @param liquidityMiningSetupsBytes array of liquidity mining setups as bytes.
      * @param setPinned if we are setting the pinned setup or not.
      * @param pinnedIndex the pinned setup index.
     */
    function _initLiquidityMiningSetups(bytes memory liquidityMiningSetupsBytes, bool setPinned, uint256 pinnedIndex) private {
        LiquidityMiningSetup[] memory liquidityMiningSetups = abi.decode(liquidityMiningSetupsBytes, (LiquidityMiningSetup[]));
        require(liquidityMiningSetups.length > 0, "Invalid length");
        for(uint256 i = 0; i < liquidityMiningSetups.length; i++) {
            _setOrAddLiquidityMiningSetup(liquidityMiningSetups[i], true, 0);
        }
        _pinnedSetup(false, setPinned, pinnedIndex);
        // rebalance the pinned setup
        rebalancePinnedSetup();
    }


     /** @dev helper method that given a liquidity mining setup adds it to the _setups array or updates it.
      * @param data new or updated liquidity mining setup.
      * @param add if we are adding the setup or updating it.
      * @param index liquidity mining setup index.
     */
    function _setOrAddLiquidityMiningSetup(LiquidityMiningSetup memory data, bool add, uint256 index) private {
        // TODO
    }

    /** @dev helper function used to update or set the pinned free setup.
      * @param clearPinned if we're clearing the pinned setup or not.
      * @param setPinned if we're setting the pinned setup or not.
      * @param pinnedIndex new pinned setup index.
     */
    function _pinnedSetup(bool clearPinned, bool setPinned, uint256 pinnedIndex) private {
        // if we're clearing the pinned setup we must also remove the excess reward per block
        if (clearPinned && loadBalancer.active) {
            loadBalancer.active = false;
            _calculateRewardPerToken(loadBalancer.setupIndex, 0, false);
        }
        // check if we're updating the pinned setup
        if (!clearPinned && setPinned) {
            require(_setups[pinnedIndex].free, "Invalid pinned free setup");
            // update pinned setup index
            loadBalancer.active = true;
            loadBalancer.setupIndex = pinnedIndex;
        }
    }

    /** @dev helper method used to toggle a setup (active/deactive).
      * @param setupIndex index of the setup to activate/deactivate.
      * @param status if it's 1 we're activating the setup, else we're deactivating it.
     */
    function _toggleSetup(uint256 setupIndex, uint256 status) private {
        uint256 amount;
        if (status == 1 && !_setups[setupIndex].active) {
            amount = _setups[setupIndex].rewardPerBlock * (_setups[setupIndex].endBlock - _setups[setupIndex].startBlock);
            try ILiquidityMiningExtension(_extension).transferTo(amount) {
                // transaction successful, activate the setup
                _setups[setupIndex].active = true;
            } catch {}
        } else if (status != 1 && _setups[setupIndex].active && (_setups[setupIndex].free || block.number < _setups[setupIndex].startBlock)) {
            amount = _setups[setupIndex].rewardPerBlock * (_setups[setupIndex].endBlock - max(block.number, _setups[setupIndex].startBlock));
            ILiquidityMiningExtension(_extension).backToYou(amount);
            // we're deactivating the setup
            _setups[setupIndex].active = false;
        }
    }

    /** @dev Renews the setup with the given index.
      * @param setupIndex index of the setup to renew.
      * @return newIndex new setup index
     */
    function _renewSetup(uint256 setupIndex) private returns (uint256 newIndex) {
        // TODO
    }

    /** @dev function used to rebalance the reward per block in the load balancer.
      * @param rewardPerBlock liquidity mining position locked reward per block that must be added or subtracted from the load balancer setup reward per block.
      * @param fromExit if the rebalance is caused by an exit from the locked liquidity mining position or not.
      */
    function _updateLoadBalancer(uint256 rewardPerBlock, bool fromExit) private {
        // TODO
        if (loadBalancer.active && _setups[loadBalancer.setupIndex].free) {
            _calculateRewardPerToken(loadBalancer.setupIndex, 0, fromExit);
        }
        fromExit ? loadBalancer.rewardPerBlock += rewardPerBlock : loadBalancer.rewardPerBlock -= rewardPerBlock;
    }

    /** @dev function used to rebalance the reward per token in a free liquidity mining setup.
      * @param setupIndex index of the setup to rebalance.
      * @param liquidityPoolTokenAmount amount of liquidity pool token being added.
      * @param fromExit if the rebalance is caused by an exit from the free liquidity mining position or not.
     */
    function _calculateRewardPerToken(uint256 setupIndex, uint256 liquidityPoolTokenAmount, bool fromExit) private {
        LiquidityMiningSetup storage setup = _setups[setupIndex];
        uint256 updateBlock = min(block.number, setup.endBlock);
        if (setup.totalSupply == 0) {
            uint256 elapsedBlocks = block.number - max(setup.lastBlockUpdate, setup.startBlock);
            uint256 amount = setup.rewardPerBlock * elapsedBlocks;
            if (amount > 0) {
                ILiquidityMiningExtension(_extension).backToYou(amount);
            }
        }
        if (setup.lastBlockUpdate > 0 && (updateBlock != _setups[setupIndex].endBlock || updateBlock != setup.lastBlockUpdate)) {
            _setupUpdateBlocks[setupIndex].push(updateBlock);
            uint256 rpb = setup.rewardPerBlock;
            // check if the setup is the current setup
            if (loadBalancer.active && loadBalancer.setupIndex == setupIndex) {
                rpb += loadBalancer.rewardPerBlock;
            }
            // update the reward token
            _rewardPerTokenPerSetupPerBlock[setupIndex][updateBlock] = (((updateBlock - setup.lastBlockUpdate) * rpb) * 1e18) / setup.totalSupply;
            // update total supply in the setup AFTER the reward calculation - to let previous liquidity mining position holders to calculate the correct value
            fromExit ? setup.totalSupply -= liquidityPoolTokenAmount : setup.totalSupply += liquidityPoolTokenAmount;
        }
        // update the last block update variable
        setup.lastBlockUpdate = updateBlock;
    }

    /** @dev this function performs the transfer of the tokens that will be staked, interacting with the AMM plugin.
      * @param setup the chosen setup.
      * @param request new open position request.
      * @return amm AMM plugin interface.
      * @return liquidityPoolAmount amount of liquidity pool token.
      * @return mainTokenAmount amount of main token staked.
      * @return involvingETH if the inputed flag is consistent.
     */
    function _transferToMeAndCheckAllowance(LiquidityMiningSetup memory setup, LiquidityMiningPositionRequest memory request) private returns(IAMM amm, uint256 liquidityPoolAmount, uint256 mainTokenAmount, bool involvingETH) {
        require(request.amount > 0, "No amount");
        involvingETH = request.amountIsLiquidityPool && setup.involvingETH;
        // retrieve the values
        amm = IAMM(setup.ammPlugin);
        liquidityPoolAmount = request.amountIsLiquidityPool ? request.amount : 0;
        mainTokenAmount = request.amountIsLiquidityPool ? 0 : request.amount;
        address[] memory tokens;
        uint256[] memory tokenAmounts;
        // if liquidity pool token amount is provided, the position is opened by liquidity pool token amount
        if(request.amountIsLiquidityPool) {
            _safeTransferFrom(setup.liquidityPoolTokenAddress, msg.sender, address(this), liquidityPoolAmount);
            (tokenAmounts, tokens) = amm.byLiquidityPoolAmount(setup.liquidityPoolTokenAddress, liquidityPoolAmount);
        } else {
            // else it is opened by the tokens amounts
            (liquidityPoolAmount, tokenAmounts, tokens) = amm.byTokenAmount(setup.liquidityPoolTokenAddress, setup.mainTokenAddress, mainTokenAmount);
        }

        // check if the eth is involved in the request
        address ethAddress = address(0); 
        if(setup.involvingETH) {
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
            if(setup.involvingETH && ethAddress == tokens[i]) {
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
      * @param amount amount of to mint for a farm token.
      * @param setupIndex index of the setup.
      * @return objectId new liquidityMiningPosition token object id.
     */
    function _mintLiquidity(address uniqueOwner, uint256 amount, uint256 setupIndex) private returns(uint256 objectId) {
        if (_setups[setupIndex].objectId == 0) {
            (objectId,) = INativeV1(_liquidityFarmTokenCollection).mint(amount, string(abi.encodePacked("Farming LP ", _toString(_setups[setupIndex].liquidityPoolTokenAddress))), "fLP", ILiquidityMiningFactory(_factory).getLiquidityFarmTokenURI(), true);
            emit FarmToken(objectId, _setups[setupIndex].liquidityPoolTokenAddress, setupIndex, _setups[setupIndex].endBlock);
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
            _setups[setupIndex].liquidityPoolTokenAddress,
            removedLiquidity,
            _setups[setupIndex].mainTokenAddress,
            true,
            _setups[setupIndex].involvingETH,
            msg.sender
        );
        // retrieve the position
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionId];
        // remaining liquidity
        uint256 remainingLiquidity;
        // we are removing liquidity using the setup items
        if (_setups[liquidityMiningPosition.setupIndex].free && liquidityMiningPosition.creationBlock != 0 && positionId != 0) {
            // update the remaining liquidity
            remainingLiquidity = liquidityMiningPosition.liquidityPoolTokenAmount - removedLiquidity;
        }
        // retrieve fee stuff
        (uint256 exitFeePercentage, address exitFeeWallet) = ILiquidityMiningFactory(_factory).feePercentageInfo();
        // pay the fees!
        if (exitFeePercentage > 0) {
            uint256 fee = (lpData.amount * ((exitFeePercentage * 1e18) / ONE_HUNDRED)) / 1e18;
            _safeTransfer(_setups[setupIndex].liquidityPoolTokenAddress, exitFeeWallet, fee);
            lpData.amount = lpData.amount - fee;
        }
        // check if the user wants to unwrap its pair or not
        if (unwrapPair) {
            // remove liquidity using AMM
            address ammPlugin = _setups[setupIndex].ammPlugin;
            _safeApprove(lpData.liquidityPoolAddress, ammPlugin, lpData.amount);
            (, uint256[] memory amounts, address[] memory tokens) = IAMM(ammPlugin).removeLiquidity(lpData);
            if (isUnlock) {
                for (uint256 i = 0; i < tokens.length; i++) {
                    if (tokens[i] == _setups[setupIndex].mainTokenAddress) {
                        _setups[setupIndex].currentlyStaked -= amounts[0];
                        break;
                    }
                }
            }
        } else {
            // send back the liquidity pool token amount without the fee
            _safeTransfer(lpData.liquidityPoolAddress, lpData.receiver, lpData.amount);
        }
        // TODO
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

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

}