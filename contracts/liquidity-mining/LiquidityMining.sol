//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./ILiquidityMiningFactory.sol";
import "../amm-aggregator/common/AMMData.sol";
import "../amm-aggregator/common/IAMM.sol";
import "./util/IERC20.sol";
import "./util/IERC20Mintable.sol";
import "./util/IEthItemOrchestrator.sol";
import "./util/INativeV1.sol";
import "./util/Math.sol";
import "./util/SafeMath.sol";
import "./FarmingSetup.sol";
import "./ILiquidityMiningExtension.sol";

contract LiquidityMining {
    // SafeMath library
    using SafeMath for uint256;

    // event that tracks setup indexes and their main tooen and secondary tokens
    event NewFarmingSetup(uint256 setupIndex, address indexed mainToken, address[] indexed secondaryTokens);
    // new position event
    event NewPosition(bytes32 positionKey, address indexed owner);
    // event that tracks liquidity mining contracts deployed
    event LiquidityMiningInitialized(address indexed contractAddress, address indexed rewardTokenAddress);
    // event that tracks ownership changes
    event OwnerChanged(bytes32 positionKey, address indexed oldOwner, address indexed newOwner);

    // position struct
    struct Position {
        uint256 objectId; // object id representing the position token if minted, 0 if uniqueOwner is populated.
        address uniqueOwner; // address representing the owner address, address(0) if objectId is populated.
        FarmingSetup setup; // chosen setup when the position was created.
        LiquidityPoolData liquidityPoolData; // amm liquidity pool data.
        uint256 liquidityPoolTokenAmount; // amount of liquidity pool token provided.
        uint256 reward; // position reward.
        uint256 lockedRewardPerBlock; // position locked reward per block.
        uint256 creationBlock; // block when this position was created.
    }

    // stake data struct
    struct StakeData {
        uint256 setupIndex; // index of the chosen setup.
        address secondaryTokenAddress; // address of the secondary token.
        uint256 liquidityPoolTokenAmount; // amount of liquidity pool token.
        uint256 mainTokenAmount; // amount of main token.
        uint256 secondaryTokenAmount; // amount of secondary token.
        address positionOwner; // position owner or address(0) [msg.sender].
        bool mintPositionToken; // if the position will be represented by a minted item or not.
    }

    // factory address that will create clones of this contract
    address public _factory;
    // address of the owner of this contract
    address public _owner;
    // address of the reward token
    address private _rewardTokenAddress;
    // position token collection
    address public _positionTokenCollection;
    // whether the token is by mint or by reserve
    bool public _byMint;
    // array containing all the currently available farming setups
    FarmingSetup[] public _farmingSetups;
    // mapping containing all the positions
    mapping(bytes32 => Position) public _positions;
    // mapping containing the reward per token per setup per block
    mapping(uint256 => mapping(uint256 => uint256)) public _rewardPerTokenPerSetupPerBlock;
    // mapping containing all the blocks where an update has been triggered
    mapping(uint256 => uint256[]) public _setupUpdateBlocks;
    // mapping containing whether a position has been redeemed or not
    mapping(bytes32 => bool) public _positionRedeemed;
    // mapping containing whether a position has been partially reedemed or not
    mapping(bytes32 => uint256) public _partiallyRedeemed;
    // mapping containing whether a locked setup has ended or not and has been used for the rebalance
    mapping(uint256 => bool) public _finishedLockedSetups;
    // pinned setup index
    uint256 public _pinnedSetupIndex;

    /** Modifiers. */

    /** @dev onlyFactory modifier used to check for unauthorized initializations. */
    modifier onlyFactory() {
        require(msg.sender == _factory, "Unauthorized.");
        _;
    }

    /** @dev onlyOwner modifier used to check for unauthorized changes. */
    modifier onlyOwner() {
        require(msg.sender == _owner, "Unauthorized.");
        _;
    }

    /** Public owner methods. */

    /** @dev function called by the factory contract to initialize a new clone.
      * @param owner liquidity mining contract owner (a wallet or an extension).
      * @param ownerInitData encoded call function of the owner (used from an extension).
      * @param orchestrator ethItemOrchestrator address.
      * @param name ethItem position token name.
      * @param symbol ethitem position token symbol.
      * @param collectionUri ethItem position token uri.
      * @param rewardTokenAddress the address of the reward token.
      * @param byMint whether the rewardToken must be rewarded by minting or by reserve.
      * @return initSuccess success if the initialize function has ended properly.
     */
    function initialize(address owner, bytes memory ownerInitData, address orchestrator, string memory name, string memory symbol, string memory collectionUri, address rewardTokenAddress, bool byMint) public returns(bool initSuccess) {
        require(
            _factory == address(0),
            "Already initialized."
        );
        _factory = msg.sender;
        _owner = owner;
        _rewardTokenAddress = rewardTokenAddress;
        (_positionTokenCollection,) = IEthItemOrchestrator(orchestrator).createNative(abi.encodeWithSignature("init(string,string,bool,string,address,bytes)", name, symbol, false, collectionUri, address(this), ""), "");
        _byMint = byMint;
        if (keccak256(ownerInitData) != keccak256("")) {
            (bool result,) = _owner.call(ownerInitData);
            require(result, "Error while initializing owner.");
        }
        emit LiquidityMiningInitialized(address(this), _rewardTokenAddress);
        initSuccess = true;
    }

    /** @dev allows the owner to set the farming setups.
      * @param farmingSetups farming setups to set.
      * @param setPinned if we're updating the pinned setup or not.
      * @param pinnedIndex new pinned setup index.
      */
    function setFarmingSetups(FarmingSetup[] memory farmingSetups, uint256[] memory farmingSetupIndexes, bool setPinned, uint256 pinnedIndex) public onlyOwner {
        for (uint256 i = 0; i < farmingSetups.length; i++) {
            if (_farmingSetups.length == 0 || farmingSetupIndexes.length == 0 || farmingSetupIndexes[i] > _farmingSetups.length) {
                // adding new farming setup
                _farmingSetups.push(farmingSetups[i]);
            } else {
                FarmingSetup storage farmingSetup = _farmingSetups[farmingSetupIndexes[i]];
                if (farmingSetup.free) {
                    // update free farming setup reward per block
                    if (farmingSetups[i].rewardPerBlock - farmingSetup.rewardPerBlock < 0) {
                        _rebalanceRewardPerBlock(farmingSetupIndexes[i], farmingSetup.rewardPerBlock - farmingSetups[i].rewardPerBlock, false);
                    } else {
                        _rebalanceRewardPerBlock(farmingSetupIndexes[i], farmingSetups[i].rewardPerBlock - farmingSetup.rewardPerBlock, true);
                    }
                } else {
                    // update locked farming setup
                    farmingSetup.rewardPerBlock = farmingSetups[i].rewardPerBlock;
                    farmingSetup.maximumLiquidity = farmingSetups[i].maximumLiquidity != 0 ? farmingSetups[i].maximumLiquidity : farmingSetup.maximumLiquidity;
                    farmingSetup.secondaryTokenAddresses = farmingSetups[i].secondaryTokenAddresses.length > 0 ? farmingSetups[i].secondaryTokenAddresses : farmingSetup.secondaryTokenAddresses;
                    farmingSetup.renewable = farmingSetups[i].renewable;
                    farmingSetup.penaltyFee = farmingSetups[i].penaltyFee;
                }
            }
            emit NewFarmingSetup(i, farmingSetups[i].mainTokenAddress, farmingSetups[i].secondaryTokenAddresses);
        }
        // update the pinned setup
        if (setPinned) {
            // update reward per token of old pinned setup
            _rebalanceRewardPerToken(_pinnedSetupIndex, 0, false);
            // update pinned setup index
            _pinnedSetupIndex = pinnedIndex;
            // update reward per token of new pinned setup
            _rebalanceRewardPerToken(_pinnedSetupIndex, 0, false);
        }
    }

    /** Public methods. */

    /** @dev returns the position token balance of the given position.
      * @param positionKey bytes32 position key.
      * @return balance position token balance.
     */
    function balanceOf(bytes32 positionKey) public view returns(uint256 balance) {
        balance = INativeV1(_positionTokenCollection).balanceOf(msg.sender, _positions[positionKey].objectId);
    }

    /** @dev this function allows a wallet to update the owner of the given position.
      * @param positionKey key of the position.
      * @param setupIndex index of the setup of the position.
      * @param newOwner address of the new owner.
     */
    function changePositionOwner(bytes32 positionKey, uint256 setupIndex, address newOwner) public {
        // retrieve position
        Position storage position = _positions[positionKey];
        require(
            position.objectId == 0 && 
            position.setup.ammPlugin != address(0) && 
            newOwner != address(0) && 
            position.setup.startBlock == _farmingSetups[setupIndex].startBlock &&
            position.setup.endBlock == _farmingSetups[setupIndex].endBlock,
        "Invalid position.");
        bytes32 newPositionKey = keccak256(abi.encode(newOwner, setupIndex, position.creationBlock));
        // copy the position to the new key
        position.uniqueOwner = newOwner;
        _positions[newPositionKey] = position;
        _positionRedeemed[newPositionKey] = _positionRedeemed[positionKey];
        _partiallyRedeemed[newPositionKey] = _partiallyRedeemed[positionKey];
        _positions[positionKey] = _positions[0x0];
        // emit owner changed event
        emit OwnerChanged(positionKey, msg.sender, newOwner);
    }

    /** @dev function called by external users to open a new position.
      * @param stakeData staking input data.
    */
    function stake(StakeData memory stakeData) public returns(bytes32) {
        require(stakeData.setupIndex < _farmingSetups.length, "Invalid setup index.");
        // retrieve the setup
        FarmingSetup storage chosenSetup = _farmingSetups[stakeData.setupIndex];
        require(_isAcceptedToken(chosenSetup.secondaryTokenAddresses, stakeData.secondaryTokenAddress), "Invalid secondary token.");
        if (!chosenSetup.free && (chosenSetup.endBlock <= block.number || chosenSetup.startBlock > block.number)) {
            revert("Setup not available.");
        }
        // retrieve the unique owner
        address uniqueOwner = (stakeData.positionOwner != address(0)) ? stakeData.positionOwner : msg.sender;
        LiquidityPoolData memory liquidityPoolData;
        IAMM ammPlugin = IAMM(chosenSetup.ammPlugin);
        // create tokens array
        address[] memory tokens = ammPlugin.tokens(chosenSetup.liquidityPoolTokenAddress);
        if (stakeData.mainTokenAmount > 0 && stakeData.secondaryTokenAmount > 0) {
            // create amounts array
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = tokens[0] == chosenSetup.mainTokenAddress ? stakeData.mainTokenAmount : stakeData.secondaryTokenAmount;
            amounts[1] = tokens[1] == chosenSetup.mainTokenAddress ? stakeData.mainTokenAmount : stakeData.secondaryTokenAmount;
            // create the liquidity pool data
            liquidityPoolData = LiquidityPoolData(
                chosenSetup.liquidityPoolTokenAddress,
                stakeData.liquidityPoolTokenAmount,
                tokens,
                amounts,
                msg.sender,
                address(this)
            );
            // retrieve the poolTokenAmount from the amm
            (liquidityPoolData.liquidityPoolAmount, amounts) = ammPlugin.addLiquidity(liquidityPoolData);
            stakeData.mainTokenAmount = amounts[tokens[0] == chosenSetup.mainTokenAddress ? 0 : 1];
            stakeData.secondaryTokenAmount = amounts[tokens[1] == chosenSetup.mainTokenAddress ? 1 : 0];
        } else if (stakeData.liquidityPoolTokenAmount > 0) {
            // open position using liquidity pool token
            _safeTransferFrom(chosenSetup.liquidityPoolTokenAddress, msg.sender, address(this), stakeData.liquidityPoolTokenAmount);
            // create the liquidity pool data for latter removal if requested
            liquidityPoolData = LiquidityPoolData(
                chosenSetup.liquidityPoolTokenAddress,
                stakeData.liquidityPoolTokenAmount,
                tokens,
                new uint256[](0),
                address(this),
                address(this)
            );
        } else {
            revert("No tokens.");
        }
        // create the default position key variable
        uint256 objectId;
        if (stakeData.mintPositionToken) {
            // user wants position token
            objectId = _mintPosition(uniqueOwner); // update 0 with positionToken objectId
        }
        // calculate the reward
        uint256 reward;
        uint256 lockedRewardPerBlock;
        if (!chosenSetup.free) {
            (reward, lockedRewardPerBlock) = _calculateLockedFarmingSetupReward(chosenSetup, stakeData.mainTokenAmount);
            require(reward > 0 && lockedRewardPerBlock > 0, "Insufficient staked amount");
            ILiquidityMiningExtension(_owner).transferTo(reward, address(this));
            chosenSetup.currentRewardPerBlock += lockedRewardPerBlock;
        }
        // retrieve position for the key
        Position storage position = _positions[objectId != 0 ? keccak256(abi.encode(objectId, block.number)) : keccak256(abi.encode(uniqueOwner, stakeData.setupIndex, block.number))];
        if (stakeData.mintPositionToken || (position.objectId == 0 && position.uniqueOwner == address(0))) {
            // creating a new position
            _positions[objectId != 0 ? keccak256(abi.encode(objectId, block.number)) : keccak256(abi.encode(uniqueOwner, stakeData.setupIndex, block.number))] = Position(
                {
                    objectId: objectId,
                    uniqueOwner: objectId == 0 ? uniqueOwner : address(0),
                    setup: chosenSetup,
                    liquidityPoolData: liquidityPoolData,
                    liquidityPoolTokenAmount: liquidityPoolData.liquidityPoolAmount,
                    reward: reward,
                    lockedRewardPerBlock: lockedRewardPerBlock,
                    creationBlock: block.number
                }
            );
        }
        if (chosenSetup.free) {
            _rebalanceRewardPerToken(stakeData.setupIndex, liquidityPoolData.liquidityPoolAmount, false);
        } else {
            _rebalanceRewardPerBlock(_pinnedSetupIndex, lockedRewardPerBlock, false);
        }
        emit NewPosition(objectId != 0 ? keccak256(abi.encode(objectId, block.number)) : keccak256(abi.encode(uniqueOwner, stakeData.setupIndex, block.number)), uniqueOwner);
        return objectId != 0 ? keccak256(abi.encode(objectId, block.number)) : keccak256(abi.encode(uniqueOwner, stakeData.setupIndex, block.number));
    }

    /** @dev this function allows a user to withdraw a partial reward.
      * @param positionKey position key.
      * @param setupIndex index of the farming setup.
     */
    function partialReward(bytes32 positionKey, uint256 setupIndex) public {
        // retrieve position
        Position storage position = _positions[positionKey];
        // check if wallet is withdrawing using a position token
        bool hasPositionItem = position.objectId != 0;
        // check if position is valid
        require(hasPositionItem || position.uniqueOwner == msg.sender, "Invalid caller.");
        require(position.setup.free || position.setup.endBlock >= block.number, "Invalid partial reward!");
        require(position.setup.ammPlugin != address(0), "Invalid position.");
        if (hasPositionItem && !(INativeV1(_positionTokenCollection).balanceOf(msg.sender, position.objectId) == 1)) {
            revert("Invalid caller.");
        }
        // update owner if has position item
        hasPositionItem ? position.uniqueOwner = msg.sender : position.uniqueOwner = position.uniqueOwner;
        if (!position.setup.free) {
            // check if reward is available
            require(position.reward > 0, "No reward!");
            // calculate the reward from the position creation block to the current block multiplied by the reward per block
            uint256 reward = (block.number >= position.setup.endBlock) ? position.reward : (block.number.sub(position.creationBlock)).mul(position.lockedRewardPerBlock);
            require(reward <= position.reward, "Reward is bigger than expected!");
            // remove the partial reward from the position total reward
            position.reward = position.reward.sub(reward);
            // withdraw the values using the helper
            _withdrawHelper(positionKey, setupIndex, false, reward, true);
        } else {
            // withdraw the values
            _withdrawHelper(positionKey, setupIndex, false, _calculateFreeFarmingSetupReward(setupIndex, positionKey), true);
            // update the position creation block to exclude all the rewarded blocks
            position.creationBlock = block.number;
        }
        // remove owner if has position item
        hasPositionItem ? position.uniqueOwner = address(0) : position.uniqueOwner = position.uniqueOwner;
    }


    /** @dev this function allows a owner to unlock its locked position receiving back its tokens or the lpt amount.
      * @param positionKey position key.
      * @param setupIndex index of the farming setup.
      * @param unwrapPair if the caller wants to unwrap his pair from the liquidity pool token or not.
      */
    function unlock(bytes32 positionKey, uint256 setupIndex, bool unwrapPair) public {
        require(positionKey != 0x0 && setupIndex <= _farmingSetups.length, "Invalid key");
        // retrieve position
        Position storage position = _positions[positionKey];
        // check if wallet is withdrawing using a position token
        bool hasPositionItem = position.objectId != 0;
        // check if position is valid
        require(hasPositionItem || position.uniqueOwner == msg.sender, "Invalid caller.");
        require(position.setup.ammPlugin != address(0), "Invalid position.");
        require(!position.setup.free && position.setup.endBlock >= block.number, "Invalid unlock!");
        require(!_positionRedeemed[positionKey], "Position already redeemed!");
        uint256 amount = _partiallyRedeemed[positionKey];
        if (amount > 0) {
            // has partially redeemed, must pay a penalty fee
            amount += _partiallyRedeemed[positionKey].mul(position.setup.penaltyFee.mul(1e18).div(100)).div(1e18);
            _safeTransferFrom(_rewardTokenAddress, msg.sender, address(this), amount);
            IERC20(_rewardTokenAddress).approve(_owner, amount);
            ILiquidityMiningExtension(_owner).backToYou(amount);
        }
        _exit(positionKey, setupIndex, unwrapPair);
    }

    /** @dev this function allows a owner to withdraw its position using its position token or not.
      * @param positionKey position key.
      * @param setupIndex index of the farming setup.
      * @param unwrapPair if the caller wants to unwrap his pair from the liquidity pool token or not.
      */
    function withdraw(bytes32 positionKey, uint256 setupIndex, bool unwrapPair) public {
        // retrieve position
        Position storage position = _positions[positionKey];
        // check if wallet is withdrawing using a position token
        bool hasPositionItem = position.objectId != 0;
        // check if position is valid
        require(hasPositionItem || position.uniqueOwner == msg.sender, "Invalid caller.");
        require(position.setup.ammPlugin != address(0), "Invalid position.");
        require(position.setup.free || position.setup.endBlock <= block.number, "Invalid withdraw!");
        require(!_positionRedeemed[positionKey], "Position already redeemed!");
        hasPositionItem ? _burnPosition(positionKey, msg.sender, position, setupIndex, unwrapPair, false) : _withdraw(positionKey, position.reward, setupIndex, unwrapPair, false);
        _positionRedeemed[positionKey] = true;
    }

    /** @dev returns the reward token address and if it's rewarded by mint or not
      * @return reward token address, byMint tuple.
     */
    function getRewardTokenData() public view returns(address, bool) {
        return (_rewardTokenAddress, _byMint);
    }

    /** @dev returns the position associated with the input key.
      * @param key position key.
      * @return position stored at the given key.
     */
    function getPosition(bytes32 key) public view returns(Position memory) {
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
      * @param expiredSetupIndexes array containing the indexes of all the expired locked farming setups.
     */
    function rebalancePinnedSetup(uint256[] memory expiredSetupIndexes) public {
        for (uint256 i = 0; i < expiredSetupIndexes.length; i++) {
            if (!_farmingSetups[expiredSetupIndexes[i]].free && block.number >= _farmingSetups[expiredSetupIndexes[i]].endBlock && !_finishedLockedSetups[expiredSetupIndexes[i]]) {
                _finishedLockedSetups[expiredSetupIndexes[i]] = !_farmingSetups[expiredSetupIndexes[i]].renewable;
                _rebalanceRewardPerBlock(_pinnedSetupIndex, _farmingSetups[expiredSetupIndexes[i]].currentRewardPerBlock, true);
                if (_farmingSetups[expiredSetupIndexes[i]].renewable) {
                    _renewSetup(expiredSetupIndexes[i]);
                }
            }
        }
    }

    /** Private methods. */

    /** @dev function used to calculate the reward in a locked farming setup.
      * @param setup farming setup.
      * @param mainTokenAmount amount of main token.
      * @return reward total reward for the position owner.
      * @return relativeRewardPerBlock returned for the pinned free setup balancing.
     */
    function _calculateLockedFarmingSetupReward(FarmingSetup storage setup, uint256 mainTokenAmount) private view returns(uint256 reward, uint256 relativeRewardPerBlock) {
        // get amount of remaining blocks
        require(setup.endBlock.sub(block.number) > 0, "Setup ended!");
        // get total reward still available (= 0 if rewardPerBlock = 0)
        require(setup.rewardPerBlock.mul(setup.endBlock.sub(block.number)) > 0, "No rewards!");
        // calculate relativeRewardPerBlock
        relativeRewardPerBlock = setup.rewardPerBlock.mul((mainTokenAmount.mul(1e18).div(setup.maximumLiquidity))).div(1e18);
        // check if rewardPerBlock is greater than 0
        require(relativeRewardPerBlock > 0, "relativeRewardPerBlock must be greater than 0.");
        // calculate reward by multiplying relative reward per block and the remaining blocks
        reward = relativeRewardPerBlock.mul(setup.endBlock.sub(block.number));
        // check if the reward is still available
        require(reward <= setup.rewardPerBlock.mul(setup.endBlock.sub(block.number)), "No availability.");
    }

    /** @dev function used to calculate the reward in a free farming setup.
      * @param setupIndex index of the farming setup.
      * @param positionKey wallet position key.
      * @return reward total reward for the position owner.
     */
    function _calculateFreeFarmingSetupReward(uint256 setupIndex, bytes32 positionKey) public view returns(uint256 reward) {
        Position memory position = _positions[positionKey];
        for (uint256 i = 0; i < _setupUpdateBlocks[setupIndex].length; i++) {
            if (position.creationBlock < _setupUpdateBlocks[setupIndex][i]) {
                reward += _rewardPerTokenPerSetupPerBlock[setupIndex][_setupUpdateBlocks[setupIndex][i]].div(1e18).mul(position.liquidityPoolTokenAmount);
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

    /** @dev mints a new PositionToken inside the collection for the given wallet.
      * @param uniqueOwner position token owner.
      * @return objectId new position token object id.
     */
    function _mintPosition(address uniqueOwner) private returns(uint256 objectId) {
        // TODO: metadata
        (objectId,) = INativeV1(_positionTokenCollection).mint(1, "UNIFI PositionToken", "UPT", "google.com", false);
        INativeV1(_positionTokenCollection).safeTransferFrom(address(this), uniqueOwner, objectId, 1, "");
    }

    /** @dev burns a PositionToken from the collection.
      * @param positionKey wallet position key.
      * @param uniqueOwner staking position owner address.
      * @param position staking position.
      * @param setupIndex index of the farming setup.
      * @param unwrapPair if the caller wants to unwrap his pair from the liquidity pool token or not.
      * @param isPartial if it's a partial withdraw or not.
      */
    function _burnPosition(bytes32 positionKey, address uniqueOwner, Position memory position, uint256 setupIndex, bool unwrapPair, bool isPartial) private {
        INativeV1 positionCollection = INativeV1(_positionTokenCollection);
        require(position.objectId != 0 && positionCollection.balanceOf(uniqueOwner, position.objectId) == 1, "Invalid position!");
        // transfer the position token to this contract
        positionCollection.asInteroperable(position.objectId).transferFrom(uniqueOwner, address(this), positionCollection.toInteroperableInterfaceAmount(position.objectId, 1));
        // burn the position token
        positionCollection.burn(position.objectId, 1);
        // withdraw the position
        _positions[positionKey].uniqueOwner = uniqueOwner;
        _withdraw(positionKey, position.reward, setupIndex, unwrapPair, isPartial);
    }

    /** @dev helper function that performs the exit of the given position for the given setup index and unwraps the pair if the owner has chosen to do so.
      * @param positionKey bytes32 key of the position.
      * @param setupIndex setup that we are exiting.
      * @param unwrapPair if the owner wants to unwrap the pair or not.
     */
    function _exit(bytes32 positionKey, uint256 setupIndex, bool unwrapPair) private {
        Position storage position = _positions[positionKey];
        uint256 exitFee = ILiquidityMiningFactory(_factory)._exitFee();
        // pay the fees!
        if (exitFee > 0) {
            uint256 fee = position.liquidityPoolData.liquidityPoolAmount.mul(exitFee.mul(1e18).div(100)).div(1e18);
            _safeTransfer(position.setup.liquidityPoolTokenAddress, _owner, fee);
            position.liquidityPoolData.liquidityPoolAmount = position.liquidityPoolData.liquidityPoolAmount.sub(fee);
        }
        // check if the user wants to unwrap its pair or not
        if (unwrapPair) {
            // remove liquidity using AMM
            position.liquidityPoolData.sender = address(this);
            position.liquidityPoolData.receiver = position.uniqueOwner;
            _safeApprove(position.liquidityPoolData.liquidityPoolAddress, position.setup.ammPlugin, position.liquidityPoolData.liquidityPoolAmount);
            uint256[] memory amounts = IAMM(position.setup.ammPlugin).removeLiquidity(position.liquidityPoolData);
            require(amounts[0] > 0 && amounts[1] > 0, "Insufficient amount.");
        } else {
            // send back the liquidity pool token amount without the fee
            _safeTransfer(position.setup.liquidityPoolTokenAddress, position.uniqueOwner, position.liquidityPoolData.liquidityPoolAmount);
        }
        // rebalance the setup if not free
        if (!_farmingSetups[setupIndex].free && !_finishedLockedSetups[setupIndex]) {
            // check if the setup has been updated or not
            if (position.setup.endBlock == _farmingSetups[setupIndex].endBlock) {
                // the locked setup must be considered finished only if it's not renewable
                _finishedLockedSetups[setupIndex] = !_farmingSetups[setupIndex].renewable;
                //_rebalanceRewardPerBlock(position.lockedRewardPerBlock, true);
                _rebalanceRewardPerBlock(_pinnedSetupIndex, _farmingSetups[setupIndex].currentRewardPerBlock, true);
                if (_farmingSetups[setupIndex].renewable) {
                    // renew the setup if renewable
                    _renewSetup(setupIndex);
                }
            }
        }
        // delete the position after the withdraw
        _positions[positionKey] = _positions[0x0];
    }

    /** @dev Renews the setup with the given index.
      * @param setupIndex index of the setup to renew.
     */
    function _renewSetup(uint256 setupIndex) private {
        uint256 duration = _farmingSetups[setupIndex].endBlock - _farmingSetups[setupIndex].startBlock;
        _farmingSetups[setupIndex].startBlock = block.number + 1;
        _farmingSetups[setupIndex].endBlock = block.number + 1 + duration;
        _farmingSetups[setupIndex].currentRewardPerBlock = 0;
    }

    /** @dev allows the wallet to withdraw its position.
      * @param positionKey staking position key.
      * @param reward staking position reward.
      * @param setupIndex index of the farming setup.
      * @param unwrapPair if the caller wants to unwrap his pair from the liquidity pool token or not.
      * @param isPartial if it's a partial withdraw or not.
      */
    function _withdraw(bytes32 positionKey, uint256 reward, uint256 setupIndex, bool unwrapPair, bool isPartial) private {
        _withdrawHelper(positionKey, setupIndex, unwrapPair, reward, isPartial);
    }

    /** @dev withdraw helper method.
      * @param positionKey staking position key.
      * @param setupIndex index of the farming setup.
      * @param unwrapPair if the caller wants to unwrap his pair from the liquidity pool token or not.
      * @param reward amount to withdraw.
      * @param isPartial if it's a partial withdraw or not.
     */
    function _withdrawHelper(bytes32 positionKey, uint256 setupIndex, bool unwrapPair, uint256 reward, bool isPartial) private {
        Position memory position = _positions[positionKey];
        // rebalance setup, if free
        if (_farmingSetups[setupIndex].free && !isPartial) {
            _rebalanceRewardPerToken(setupIndex, position.liquidityPoolTokenAmount, true);
            reward = (reward == 0) ? _calculateFreeFarmingSetupReward(setupIndex, positionKey) : reward;
            require(reward > 0, "Reward cannot be 0.");
        }
        // transfer the reward
        if (reward > 0) {
            if(!position.setup.free) {
                _safeTransfer(_rewardTokenAddress, position.uniqueOwner, reward);
            } else {
                ILiquidityMiningExtension(_owner).transferTo(reward, position.uniqueOwner);
            }
        }
        if (!isPartial) {
            _exit(positionKey, setupIndex, unwrapPair);
        } else {
            _partiallyRedeemed[positionKey] = reward;
        }
    }

    /** @dev function used to rebalance the reward per block in the given free farming setup.
      * @param setupIndex setup to rebalance.
      * @param lockedRewardPerBlock new position locked reward per block that must be subtracted from the given free farming setup reward per block.
      * @param fromExit if the rebalance is caused by an exit from the locked position or not.
      */
    function _rebalanceRewardPerBlock(uint256 setupIndex, uint256 lockedRewardPerBlock, bool fromExit) private {
        FarmingSetup storage setup = _farmingSetups[setupIndex];
        _rebalanceRewardPerToken(setupIndex, 0, fromExit);
        fromExit ? setup.rewardPerBlock += lockedRewardPerBlock : setup.rewardPerBlock -= lockedRewardPerBlock;
    }

    /** @dev function used to rebalance the reward per token in a free farming setup.
      * @param setupIndex index of the setup to rebalance.
      * @param liquidityPoolTokenAmount amount of liquidity pool token being added.
      * @param fromExit if the rebalance is caused by an exit from the free position or not.
     */
    function _rebalanceRewardPerToken(uint256 setupIndex, uint256 liquidityPoolTokenAmount, bool fromExit) private {
        FarmingSetup storage setup = _farmingSetups[setupIndex];
        if(setup.lastBlockUpdate > 0 && setup.totalSupply > 0) {
            // add the block to the setup update blocks
            _setupUpdateBlocks[setupIndex].push(block.number);
            // update the reward token
            _rewardPerTokenPerSetupPerBlock[setupIndex][block.number] = (block.number.sub(setup.lastBlockUpdate)).mul(setup.rewardPerBlock).mul(1e18).div(setup.totalSupply);
        }
        // update the last block update variable
        setup.lastBlockUpdate = block.number;
        // update total supply in the setup AFTER the reward calculation - to let previous position holders to calculate the correct value
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