//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;

import "./ILiquidityMiningFactory.sol";
import "./LiquidityMiningData.sol";
import "./ILiquidityMiningExtension.sol";
import "../amm-aggregator/common/IAMM.sol";
import "./util/IERC20.sol";
import "./util/IERC20Mintable.sol";
import "./util/IEthItemOrchestrator.sol";
import "./util/INativeV1.sol";

contract LiquidityMining {

    // event that tracks liquidity mining contracts deployed
    event RewardToken(address indexed rewardTokenAddress);
    // event that tracks setup indexes and their main tooen and secondary tokens
    event NewLiquidityMiningSetup(uint256 setupIndex, address indexed mainToken, address[] indexed secondaryTokens);
    // new liquidity mining position event
    event Transfer(bytes32 indexed positionKey, address indexed from, address indexed to);

    // factory address that will create clones of this contract
    address public _factory;
    // address of the extension of this contract
    address public _extension;
    // address of the reward token
    address private _rewardTokenAddress;
    // liquidityMiningPosition token collection
    address public _positionTokenCollection;
    // whether the token is by mint or by reserve
    bool public _byMint;
    // array containing all the currently available liquidity mining setups
    LiquidityMiningSetup[] private _setups;
    // mapping containing all the positions
    mapping(bytes32 => LiquidityMiningPosition) public _positions;
    // mapping containing the reward per token per setup per block
    mapping(uint256 => mapping(uint256 => uint256)) public _rewardPerTokenPerSetupPerBlock;
    // mapping containing all the blocks where an update has been triggered
    mapping(uint256 => uint256[]) public _setupUpdateBlocks;
    // mapping containing whether a liquidity mining position has been redeemed or not
    mapping(bytes32 => bool) public _positionRedeemed;
    // mapping containing whether a liquidity mining position has been partially reedemed or not
    mapping(bytes32 => uint256) public _partiallyRedeemed;
    // mapping containing whether a locked setup has ended or not and has been used for the rebalance
    mapping(uint256 => bool) public _finishedLockedSetups;
    // pinned setup index
    bool public _hasPinned;
    uint256 public _pinnedSetupIndex;

    /** Modifiers. */

    /** @dev onlyOwner modifier used to check for unauthorized changes. */
    modifier onlyOwner() {
        require(msg.sender == _extension, "Unauthorized.");
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
      * @param byMint whether the rewardToken must be rewarded by minting or by reserve.
     */
    function initialize(address extension, bytes memory ownerInitData, address orchestrator, string memory name, string memory symbol, string memory collectionUri, address rewardTokenAddress, bool byMint) public {
        require(
            _factory == address(0),
            "Already initialized."
        );
        _factory = msg.sender;
        _extension = extension;
        _rewardTokenAddress = rewardTokenAddress;
        (_positionTokenCollection,) = IEthItemOrchestrator(orchestrator).createNative(abi.encodeWithSignature("init(string,string,bool,string,address,bytes)", name, symbol, false, collectionUri, address(this), ""), "");
        _byMint = byMint;
        if (keccak256(ownerInitData) != keccak256("")) {
            (bool result,) = _extension.call(ownerInitData);
            require(result, "Error while initializing extension.");
        }
        emit RewardToken(_rewardTokenAddress);
    }

    receive() external payable {
        require(_rewardTokenAddress == address(0) && msg.sender == _extension, "Unauthorized");
    }

    function setups() public view returns (LiquidityMiningSetup[] memory) {
        return _setups;
    }

    /** @dev allows the extension to set the liquidity mining setups.
      * @param liquidityMiningSetups liquidity mining setups to set.
      * @param setPinned if we're updating the pinned setup or not.
      * @param pinnedIndex new pinned setup index.
      */
    function setLiquidityMiningSetups(LiquidityMiningSetupConfiguration[] memory liquidityMiningSetups, bool clearPinned, bool setPinned, uint256 pinnedIndex) public onlyOwner {
        for (uint256 i = 0; i < liquidityMiningSetups.length; i++) {
            LiquidityMiningSetupConfiguration memory configuration = liquidityMiningSetups[i];
            if (configuration.add) {
                // adding new liquidity mining setup
                _setups.push(configuration.data);
            } else {
                LiquidityMiningSetup storage liquidityMiningSetup = _setups[configuration.index];
                if (liquidityMiningSetup.free) {
                    // update free liquidity mining setup reward per block
                    if (configuration.data.rewardPerBlock - liquidityMiningSetup.rewardPerBlock < 0) {
                        _rebalanceRewardPerBlock(configuration.index, liquidityMiningSetup.rewardPerBlock - configuration.data.rewardPerBlock, false);
                    } else {
                        _rebalanceRewardPerBlock(configuration.index, configuration.data.rewardPerBlock - liquidityMiningSetup.rewardPerBlock, true);
                    }
                } else {
                    // update locked liquidity mining setup
                    liquidityMiningSetup.rewardPerBlock = configuration.data.rewardPerBlock;
                    liquidityMiningSetup.maximumLiquidity = configuration.data.maximumLiquidity != 0 ? configuration.data.maximumLiquidity : liquidityMiningSetup.maximumLiquidity;
                    liquidityMiningSetup.liquidityPoolTokenAddresses = configuration.data.liquidityPoolTokenAddresses.length > 0 ? configuration.data.liquidityPoolTokenAddresses : liquidityMiningSetup.liquidityPoolTokenAddresses;
                    liquidityMiningSetup.renewable = configuration.data.renewable;
                    liquidityMiningSetup.penaltyFee = configuration.data.penaltyFee;
                }
            }
            emit NewLiquidityMiningSetup(i, configuration.data.mainTokenAddress, configuration.data.liquidityPoolTokenAddresses);
        }
        if(clearPinned) {
            _hasPinned = false;
        }
        // update the pinned setup
        if (!clearPinned && setPinned) {
            // update reward per token of old pinned setup
            _rebalanceRewardPerToken(_pinnedSetupIndex, 0, false);
            // update pinned setup index
            _hasPinned = true;
            _pinnedSetupIndex = pinnedIndex;
            // update reward per token of new pinned setup
            _rebalanceRewardPerToken(_pinnedSetupIndex, 0, false);
        }
    }

    /** Public methods. */

    /** @dev this function allows a wallet to update the extension of the given liquidity mining position.
      * @param to address of the new extension.
      * @param positionKey key of the liquidity mining position.
     */
    function transfer(address to, bytes32 positionKey) public {
        // retrieve liquidity mining position
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionKey];
        require(
            liquidityMiningPosition.objectId == 0 && 
            liquidityMiningPosition.setup.ammPlugin != address(0) && 
            to != address(0) &&
            liquidityMiningPosition.uniqueOwner == msg.sender &&
            liquidityMiningPosition.setup.startBlock == _setups[liquidityMiningPosition.setupIndex].startBlock &&
            liquidityMiningPosition.setup.endBlock == _setups[liquidityMiningPosition.setupIndex].endBlock,
        "Invalid liquidity mining position.");
        liquidityMiningPosition.uniqueOwner = to;
        emit Transfer(positionKey, msg.sender, to);
    }

    /** @dev function called by external users to open a new liquidity mining position.
      * @param request Liquidity Mining input data.
    */
    function openPosition(LiquidityMiningPositionRequest memory request) public payable returns(bytes32 positionKey) {
        require(request.setupIndex < _setups.length, "Invalid setup index.");
        // retrieve the setup
        LiquidityMiningSetup storage chosenSetup = _setups[request.setupIndex];
        require(chosenSetup.free || (block.number >= chosenSetup.startBlock && block.number <= chosenSetup.endBlock), "Setup not available.");
        require(request.liquidityPoolTokenAmount > 0 || request.mainTokenAmount > 0, "No tokens");
        (IAMM ammPlugin, address liquidityPoolAddress, address[] memory tokens, uint256 mainTokenAmount, uint256 liquidityPoolTokenAmount, uint256[] memory amounts) = _transferToMeAndCheckAllowance(chosenSetup, request);
        // retrieve the unique owner
        address uniqueOwner = (request.positionOwner != address(0)) ? request.positionOwner : msg.sender;

        LiquidityPoolData memory liquidityPoolData = LiquidityPoolData(
            liquidityPoolAddress,
            liquidityPoolTokenAmount,
            tokens,
            amounts,
            address(this)
        );

        if (request.liquidityPoolTokenAmount == 0) {
            // retrieve the poolTokenAmount from the amm
            (liquidityPoolData.liquidityPoolAmount, amounts) = ammPlugin.addLiquidity(liquidityPoolData);
        }

        uint256 objectId = request.mintPositionToken ? _mintPosition(uniqueOwner) : 0;
        positionKey = request.mintPositionToken ? bytes32(objectId) : keccak256(abi.encode(uniqueOwner, request.setupIndex, block.number));

        // calculate the reward
        uint256 reward;
        uint256 lockedRewardPerBlock;
        if (!chosenSetup.free) {
            (reward, lockedRewardPerBlock) = _calculateLockedLiquidityMiningSetupReward(chosenSetup, mainTokenAmount);
            require(reward > 0 && lockedRewardPerBlock > 0, "Insufficient staked amount");
            ILiquidityMiningExtension(_extension).transferTo(reward, address(this));
            chosenSetup.currentRewardPerBlock += lockedRewardPerBlock;
        }
        _positions[positionKey] = LiquidityMiningPosition({
            objectId: objectId,
            uniqueOwner: objectId == 0 ? uniqueOwner : address(0),
            setupIndex : request.setupIndex,
            setup: chosenSetup,
            liquidityPoolData: liquidityPoolData,
            reward: reward,
            lockedRewardPerBlock: lockedRewardPerBlock,
            creationBlock: block.number
        });
        if (chosenSetup.free) {
            _rebalanceRewardPerToken(request.setupIndex, liquidityPoolData.liquidityPoolAmount, false);
        } else {
            _rebalanceRewardPerBlock(_pinnedSetupIndex, lockedRewardPerBlock, false);
        }

        emit Transfer(positionKey, address(0), uniqueOwner);
    }

    /** @dev this function allows a user to withdraw a partial reward.
      * @param positionKey liquidity mining position key.
     */
    function partialReward(bytes32 positionKey) public {
        // retrieve liquidity mining position
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionKey];
        // check if wallet is withdrawing using a liquidity mining position token
        bool hasPositionItem = liquidityMiningPosition.objectId != 0;
        // check if liquidity mining position is valid
        require(hasPositionItem || liquidityMiningPosition.uniqueOwner == msg.sender, "Invalid caller.");
        require(liquidityMiningPosition.setup.free || liquidityMiningPosition.setup.endBlock >= block.number, "Invalid partial reward!");
        require(liquidityMiningPosition.setup.ammPlugin != address(0), "Invalid liquidityMiningPosition.");
        if (hasPositionItem && !(INativeV1(_positionTokenCollection).balanceOf(msg.sender, liquidityMiningPosition.objectId) == 1)) {
            revert("Invalid caller.");
        }
        // update extension if has liquidity mining position item
        hasPositionItem ? liquidityMiningPosition.uniqueOwner = msg.sender : liquidityMiningPosition.uniqueOwner = liquidityMiningPosition.uniqueOwner;
        if (!liquidityMiningPosition.setup.free) {
            // check if reward is available
            require(liquidityMiningPosition.reward > 0, "No reward!");
            // calculate the reward from the liquidity mining position creation block to the current block multiplied by the reward per block
            uint256 reward = (block.number >= liquidityMiningPosition.setup.endBlock) ? liquidityMiningPosition.reward : ((block.number - liquidityMiningPosition.creationBlock) * liquidityMiningPosition.lockedRewardPerBlock);
            require(reward <= liquidityMiningPosition.reward, "Reward is bigger than expected!");
            // remove the partial reward from the liquidity mining position total reward
            liquidityMiningPosition.reward = liquidityMiningPosition.reward - reward;
            // withdraw the values using the helper
            _withdraw(positionKey, false, reward, true);
        } else {
            // withdraw the values
            _withdraw(positionKey, false, _calculateFreeLiquidityMiningSetupReward(positionKey), true);
            // update the liquidity mining position creation block to exclude all the rewarded blocks
            liquidityMiningPosition.creationBlock = block.number;
        }
        // remove extension if has liquidity mining position item
        hasPositionItem ? liquidityMiningPosition.uniqueOwner = address(0) : liquidityMiningPosition.uniqueOwner = liquidityMiningPosition.uniqueOwner;
    }


    /** @dev this function allows a extension to unlock its locked liquidity mining position receiving back its tokens or the lpt amount.
      * @param positionKey liquidity mining position key.
      * @param setupIndex index of the liquidity mining setup.
      * @param unwrapPair if the caller wants to unwrap his pair from the liquidity pool token or not.
      */
    function unlock(bytes32 positionKey, uint256 setupIndex, bool unwrapPair) public payable {
        require(positionKey != 0x0 && setupIndex <= _setups.length, "Invalid key");
        // retrieve liquidity mining position
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionKey];
        // check if wallet is withdrawing using a liquidity mining position token
        bool hasPositionItem = liquidityMiningPosition.objectId != 0;
        // check if liquidity mining position is valid
        require(hasPositionItem || liquidityMiningPosition.uniqueOwner == msg.sender, "Invalid caller.");
        require(liquidityMiningPosition.setup.ammPlugin != address(0), "Invalid liquidityMiningPosition.");
        require(!liquidityMiningPosition.setup.free && liquidityMiningPosition.setup.endBlock >= block.number, "Invalid unlock!");
        require(!_positionRedeemed[positionKey], "LiquidityMiningPosition already redeemed!");
        uint256 amount = _partiallyRedeemed[positionKey];
        if (amount > 0) {
            // has partially redeemed, must pay a penalty fee
            amount += (_partiallyRedeemed[positionKey] * ((liquidityMiningPosition.setup.penaltyFee * 1e18) / 100) / 1e18);
            if(_rewardTokenAddress != address(0)) {
                _safeTransferFrom(_rewardTokenAddress, msg.sender, address(this), amount);
                _safeApprove(_rewardTokenAddress, _extension, amount);
                ILiquidityMiningExtension(_extension).backToYou(amount);
            } else {
                require(msg.value == amount, "Invalid sent amount");
                ILiquidityMiningExtension(_extension).backToYou{value : amount}(amount);
            }
        }
        _exit(positionKey, unwrapPair);
    }

    /** @dev this function allows a extension to withdraw its liquidity mining position using its liquidity mining position token or not.
      * @param positionKey liquidity mining position key.
      * @param unwrapPair if the caller wants to unwrap his pair from the liquidity pool token or not.
      */
    function withdraw(bytes32 positionKey, bool unwrapPair) public {
        // retrieve liquidity mining position
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionKey];
        // check if wallet is withdrawing using a liquidity mining position token
        bool hasPositionItem = liquidityMiningPosition.objectId != 0;
        // check if liquidity mining position is valid
        require(hasPositionItem || liquidityMiningPosition.uniqueOwner == msg.sender, "Invalid caller.");
        require(liquidityMiningPosition.setup.ammPlugin != address(0), "Invalid liquidityMiningPosition.");
        require(liquidityMiningPosition.setup.free || liquidityMiningPosition.setup.endBlock <= block.number, "Invalid withdraw!");
        require(!_positionRedeemed[positionKey], "LiquidityMiningPosition already redeemed!");
        if(hasPositionItem) {
            _burnPosition(positionKey, msg.sender, liquidityMiningPosition);
        }
        _withdraw(positionKey, unwrapPair, liquidityMiningPosition.reward, false);
        _positionRedeemed[positionKey] = true;
    }

    /** @dev returns the reward token address and if it's rewarded by mint or not
      * @return reward token address, byMint tuple.
     */
    function getRewardTokenData() public view returns(address, bool) {
        return (_rewardTokenAddress, _byMint);
    }

    /** @dev returns the liquidiliquidity mining positiontyMiningPosition associated with the input key.
      * @param key liquidity mining position key.
      * @return liquidity mining position stored at the given key.
     */
    function getPosition(bytes32 key) public view returns(LiquidityMiningPosition memory) {
        return _positions[key];
    }

    /** @dev returns the reward per token for the setup index at the given block number.
      * @param setupIndex index of the setup.
      * @param blockNumber block that wants to be inspected.
      * @return reward per token.
     */
    function getRewardPerToken(uint256 setupIndex, uint256 blockNumber) public view returns(uint256) {
        return _rewardPerTokenPerSetupPerBlock[setupIndex][blockNumber];
    }

    /** @dev this function allows any user to rebalance the pinned setup.
      * @param expiredSetupIndexes array containing the indexes of all the expired locked liquidity mining setups.
     */
    function rebalancePinnedSetup(uint256[] memory expiredSetupIndexes) public {
        for (uint256 i = 0; i < expiredSetupIndexes.length; i++) {
            if (!_setups[expiredSetupIndexes[i]].free && block.number >= _setups[expiredSetupIndexes[i]].endBlock && !_finishedLockedSetups[expiredSetupIndexes[i]]) {
                _finishedLockedSetups[expiredSetupIndexes[i]] = !_setups[expiredSetupIndexes[i]].renewable;
                _rebalanceRewardPerBlock(_pinnedSetupIndex, _setups[expiredSetupIndexes[i]].currentRewardPerBlock, true);
                if (_setups[expiredSetupIndexes[i]].renewable) {
                    _renewSetup(expiredSetupIndexes[i]);
                }
            }
        }
    }

    /** @dev adds liquidity to the liquidity mining position at the given positionKey using the given lpData.
      * @param positionKey bytes32 key of the liquidity mining position.
      * @param setupIndex setup where we want to add the liquidity.
      * @param lpData array of LiquidityPoolData.
    function addLiquidity(bytes32 positionKey, uint256 setupIndex, LiquidityPoolData[] memory lpData) public {
        // retrieve liquidity mining position
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionKey];
        // check if liquidity mining position is valid
        require(liquidityMiningPosition.objectId != 0 || liquidityMiningPosition.uniqueOwner == msg.sender, "Invalid caller.");
        require(liquidityMiningPosition.setup.free || liquidityMiningPosition.setup.endBlock >= block.number, "Invalid add liquidity!");
        require(liquidityMiningPosition.setup.ammPlugin != address(0), "Invalid liquidity mining position.");
        uint256 totalAmount;
        (uint256[] memory amounts,) = IAMM(liquidityMiningPosition.setup.ammPlugin).addLiquidityBatch(lpData);
        for (uint256 i = 0; i < lpData.length; i++) {
            totalAmount += amounts[i];
            liquidityMiningPosition.liquidityPoolTokenAmount += amounts[i];
            liquidityMiningPosition.liquidityPoolData[liquidityMiningPosition.liquidityPoolData.length + i] = lpData[i];
        }
        if (liquidityMiningPosition.setup.free) {
            _rebalanceRewardPerToken(setupIndex, totalAmount, false);
        }
    }
     */

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
        require(remainingBlocks > 0, "Setup ended!");
        // get total reward still available (= 0 if rewardPerBlock = 0)
        require(setup.rewardPerBlock * remainingBlocks > 0, "No rewards!");
        // calculate relativeRewardPerBlock
        relativeRewardPerBlock = (setup.rewardPerBlock * ((mainTokenAmount * 1e18) / setup.maximumLiquidity)) / 1e18;
        // check if rewardPerBlock is greater than 0
        require(relativeRewardPerBlock > 0, "relativeRewardPerBlock must be greater than 0.");
        // calculate reward by multiplying relative reward per block and the remaining blocks
        reward = relativeRewardPerBlock * remainingBlocks;
        // check if the reward is still available
        require(reward <= setup.rewardPerBlock * remainingBlocks, "No availability.");
    }

    /** @dev function used to calculate the reward in a free liquidity mining setup.
      * @param positionKey wallet liquidity mining position key.
      * @return reward total reward for the liquidity mining position extension.
     */
    function _calculateFreeLiquidityMiningSetupReward(bytes32 positionKey) public view returns(uint256 reward) {
        LiquidityMiningPosition memory liquidityMiningPosition = _positions[positionKey];
        for (uint256 i = 0; i < _setupUpdateBlocks[liquidityMiningPosition.setupIndex].length; i++) {
            if (liquidityMiningPosition.creationBlock < _setupUpdateBlocks[liquidityMiningPosition.setupIndex][i]) {
                reward += (_rewardPerTokenPerSetupPerBlock[liquidityMiningPosition.setupIndex][_setupUpdateBlocks[liquidityMiningPosition.setupIndex][i]] / 1e18) * liquidityMiningPosition.liquidityPoolData.liquidityPoolAmount;
            }
        }
        require(reward > 0, "No reward!");
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

    function _transferToMeAndCheckAllowance(LiquidityMiningSetup storage liquidityMiningSetup, LiquidityMiningPositionRequest memory request) private returns(IAMM amm, address liquidityPoolAddress, address[] memory tokens, uint256 mainTokenAmount, uint256 liquidityPoolTokenAmount, uint256[] memory tokenAmounts) {
        mainTokenAmount = request.mainTokenAmount;
        liquidityPoolTokenAmount = request.liquidityPoolTokenAmount;
        amm = IAMM(liquidityMiningSetup.ammPlugin);
        liquidityPoolAddress = liquidityMiningSetup.liquidityPoolTokenAddresses[request.liquidityPoolAddressIndex];
        if(liquidityPoolTokenAmount > 0) {
            _safeTransferFrom(liquidityPoolAddress, msg.sender, address(this), liquidityPoolTokenAmount);
            tokenAmounts = amm.byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolTokenAmount);
        } else {
            (liquidityPoolTokenAmount, tokenAmounts) = amm.byTokenAmount(liquidityPoolAddress, liquidityMiningSetup.mainTokenAddress, mainTokenAmount);
        }
        tokens = amm.tokens(liquidityPoolAddress);
        address ethAddress = request.ethInvolved ? amm.ethereumAddress() : address(0);
        for(uint256 i = 0; i < tokens.length; i++) {
            if(tokens[i] == liquidityMiningSetup.mainTokenAddress) {
                mainTokenAmount = tokenAmounts[i];
                if(request.liquidityPoolTokenAmount > 0) {
                    break;
                }
            }
            if(request.ethInvolved && ethAddress == tokens[i]) {
                require(msg.value == tokenAmounts[i], "Insufficient eth");
            } else {
                _safeTransferFrom(tokens[i], msg.sender, address(this), tokenAmounts[i]);
                _safeApprove(tokens[i], liquidityMiningSetup.ammPlugin, tokenAmounts[i]);
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
      * @param positionKey wallet liquidity mining position key.
      * @param uniqueOwner staking liquidity mining position extension address.
      * @param liquidityMiningPosition staking liquidity mining position.
      */
    function _burnPosition(bytes32 positionKey, address uniqueOwner, LiquidityMiningPosition memory liquidityMiningPosition) private {
        INativeV1 positionCollection = INativeV1(_positionTokenCollection);
        require(liquidityMiningPosition.objectId != 0 && positionCollection.balanceOf(uniqueOwner, liquidityMiningPosition.objectId) == 1, "Invalid liquidityMiningPosition!");
        // transfer the liquidity mining position token to this contract
        positionCollection.asInteroperable(liquidityMiningPosition.objectId).transferFrom(uniqueOwner, address(this), positionCollection.toInteroperableInterfaceAmount(liquidityMiningPosition.objectId, 1));
        // burn the liquidity mining position token
        positionCollection.burn(liquidityMiningPosition.objectId, 1);
        // withdraw the liquidityMiningPosition
        _positions[positionKey].uniqueOwner = uniqueOwner;
    }

    /** @dev helper function that performs the exit of the given liquidity mining position for the given setup index and unwraps the pair if the extension has chosen to do so.
      * @param positionKey bytes32 key of the liquidity mining position.
      * @param unwrapPair if the extension wants to unwrap the pair or not.
     */
    function _exit(bytes32 positionKey, bool unwrapPair) private {
        LiquidityMiningPosition storage liquidityMiningPosition = _positions[positionKey];
        uint256 exitFee = ILiquidityMiningFactory(_factory)._exitFee();
        // pay the fees!
        if (exitFee > 0) {
            uint256 fee = (liquidityMiningPosition.liquidityPoolData.liquidityPoolAmount * ((exitFee * 1e18) / 100)) / 1e18;
            _safeTransfer(liquidityMiningPosition.liquidityPoolData.liquidityPoolAddress, _extension, fee);
            liquidityMiningPosition.liquidityPoolData.liquidityPoolAmount = liquidityMiningPosition.liquidityPoolData.liquidityPoolAmount - fee;
        }
        // check if the user wants to unwrap its pair or not
        if (unwrapPair) {
            // remove liquidity using AMM
            liquidityMiningPosition.liquidityPoolData.receiver = liquidityMiningPosition.uniqueOwner;
            _safeApprove(liquidityMiningPosition.liquidityPoolData.liquidityPoolAddress, liquidityMiningPosition.setup.ammPlugin, liquidityMiningPosition.liquidityPoolData.liquidityPoolAmount);
            uint256[] memory amounts = IAMM(liquidityMiningPosition.setup.ammPlugin).removeLiquidity(liquidityMiningPosition.liquidityPoolData);
            require(amounts[0] > 0 && amounts[1] > 0, "Insufficient amount.");
        } else {
            // send back the liquidity pool token amount without the fee
            _safeTransfer(liquidityMiningPosition.liquidityPoolData.liquidityPoolAddress, liquidityMiningPosition.uniqueOwner, liquidityMiningPosition.liquidityPoolData.liquidityPoolAmount);
        }
        // rebalance the setup if not free
        if (!_setups[liquidityMiningPosition.setupIndex].free && !_finishedLockedSetups[liquidityMiningPosition.setupIndex]) {
            // check if the setup has been updated or not
            if (liquidityMiningPosition.setup.endBlock == _setups[liquidityMiningPosition.setupIndex].endBlock) {
                // the locked setup must be considered finished only if it's not renewable
                _finishedLockedSetups[liquidityMiningPosition.setupIndex] = !_setups[liquidityMiningPosition.setupIndex].renewable;
                //_rebalanceRewardPerBlock(liquidityMiningPosition.lockedRewardPerBlock, true);
                _rebalanceRewardPerBlock(_pinnedSetupIndex, _setups[liquidityMiningPosition.setupIndex].currentRewardPerBlock, true);
                if (_setups[liquidityMiningPosition.setupIndex].renewable) {
                    // renew the setup if renewable
                    _renewSetup(liquidityMiningPosition.setupIndex);
                }
            }
        }
        // delete the liquidity mining position after the withdraw
        _positions[positionKey] = _positions[0x0];
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
      * @param positionKey staking liquidity mining position key.
      * @param unwrapPair if the caller wants to unwrap his pair from the liquidity pool token or not.
      * @param reward amount to withdraw.
      * @param isPartial if it's a partial withdraw or not.
     */
    function _withdraw(bytes32 positionKey, bool unwrapPair, uint256 reward, bool isPartial) private {
        LiquidityMiningPosition memory liquidityMiningPosition = _positions[positionKey];
        // rebalance setup, if free
        if (_setups[liquidityMiningPosition.setupIndex].free && !isPartial) {
            _rebalanceRewardPerToken(liquidityMiningPosition.setupIndex, liquidityMiningPosition.liquidityPoolData.liquidityPoolAmount, true);
            reward = (reward == 0) ? _calculateFreeLiquidityMiningSetupReward(positionKey) : reward;
            require(reward > 0, "Reward cannot be 0.");
        }
        // transfer the reward
        if (reward > 0) {
            if(!liquidityMiningPosition.setup.free) {
                if(_rewardTokenAddress != address(0)) {
                    _safeTransfer(_rewardTokenAddress, liquidityMiningPosition.uniqueOwner, reward);
                } else {
                    payable(liquidityMiningPosition.uniqueOwner).transfer(reward);
                }
            } else {
                ILiquidityMiningExtension(_extension).transferTo(reward, liquidityMiningPosition.uniqueOwner);
            }
        }
        if (!isPartial) {
            _exit(positionKey, unwrapPair);
        } else {
            _partiallyRedeemed[positionKey] = reward;
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

    /** @dev allows the contract to retrieve the exit fee from the factory.
      * @return exitFee contract exit fee.
     */
    function _getExitFee() private returns(uint256 exitFee) {
        exitFee = ILiquidityMiningFactory(_factory)._exitFee();
    }

    /** @dev allows the contract to retrieve the wallet from the factory.
      * @return wallet external wallet for tokens.
     */
    function _getWallet() private returns(address wallet) {
        wallet = ILiquidityMiningFactory(_factory)._wallet();
    }
}