//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../amm-aggregator/common/AMMData.sol";
import "../amm-aggregator/common/IAMM.sol";
import "./util/IERC20.sol";
import "./util/IERC20Mintable.sol";
import "./util/IEthItemOrchestrator.sol";
import "./util/INativeV1.sol";
import "./util/Math.sol";
import "./util/SafeMath.sol";

contract LiquidityMining {
    // SafeMath library
    using SafeMath for uint256;

    // new position event
    event NewPosition(bytes32 positionKey);

    // farming setup struct
    struct FarmingSetup {
        address ammPlugin; // amm plugin address used for this setup (eg. uniswap amm plugin address).
        address liquidityPoolTokenAddress; // address of the liquidity pool token
        uint256 startBlock; // farming setup start block (used only if free is false).
        uint256 endBlock; // farming setup end block (used only if free is false).
        uint256 rewardPerBlock; // farming setup reward per single block.
        uint256 maximumLiquidity; // maximum total liquidity (used only if free is false).
        uint256 totalSupply; // current liquidity added in this setup (used only if free is true).
        uint256 lastBlockUpdate; // number of the block where an update was triggered.
        address mainTokenAddress; // eg. buidl address.
        address[] secondaryTokenAddresses; // eg. [address(0), dai address].
        bool free; // if the setup is a free farming setup or a locked one.
    }

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
    address public FACTORY;
    // address of the owner of this contract
    address private _owner;
    // address of the reward token
    address private _rewardTokenAddress;
    // position token collection
    address public _positionTokenCollection;
    // whether the token is by mint or by reserve
    bool private _byMint;
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
    // owner exit fee
    uint256 public _exitFee;
    // pinned setup index
    uint256 private _pinnedSetupIndex;

    /** Modifiers. */

    /** @dev onlyFactory modifier used to check for unauthorized initializations. */
    modifier onlyFactory() {
        require(msg.sender == FACTORY, "Unauthorized.");
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
            FACTORY == address(0),
            "Already initialized."
        );
        FACTORY = msg.sender;
        _owner = owner;
        _rewardTokenAddress = rewardTokenAddress;
        (_positionTokenCollection,) = IEthItemOrchestrator(orchestrator).createNative(abi.encodeWithSignature("init(string,string,bool,string,address,bytes)", name, symbol, true, collectionUri, address(this), ""), "");
        _byMint = byMint;
        if (keccak256(ownerInitData) != keccak256("")) {
            (bool result,) = _owner.call(ownerInitData);
            require(result, "Error while initializing owner.");
        }
        initSuccess = true;
    }

    /** @dev allows the owner to set the farming setups.
      * @param farmingSetups farming setups to set.
      */
    function setFarmingSetups(FarmingSetup[] memory farmingSetups) public onlyOwner {
        for (uint256 i = 0; i < farmingSetups.length; i++) {
            _farmingSetups.push(farmingSetups[i]);
        }
    }

    /** @dev allows the owner to update the exit fee.
      * @param newExitFee new exit fee value.
      */
    function setExitFee(uint256 newExitFee) public onlyOwner {
        _exitFee = newExitFee;
    }

    /** @dev updates the pinned setup index and updates the relative reward per block.
      * @param newPinnedSetupIndex new pinned setup index.
     */
    function setPinnedSetup(uint256 newPinnedSetupIndex) public onlyOwner {
        // update reward per token of old pinned setup
        _rebalanceRewardPerToken(_pinnedSetupIndex, 0, false);
        // update pinned setup index
        _pinnedSetupIndex = newPinnedSetupIndex;
        // update reward per token of new pinned setup
        _rebalanceRewardPerToken(_pinnedSetupIndex, 0, false);
    }

    /** Public methods. */

    /** @dev function called by external users to open a new position.
      * @param stakeData staking input data.
    */
    function stake(StakeData memory stakeData) public  {
        require(stakeData.setupIndex < _farmingSetups.length, "Invalid setup index.");
        // retrieve the setup
        FarmingSetup storage chosenSetup = _farmingSetups[stakeData.setupIndex];
        require(_isAcceptedToken(chosenSetup.secondaryTokenAddresses, stakeData.secondaryTokenAddress), "Invalid secondary token.");
        // retrieve the unique owner
        address uniqueOwner = (stakeData.positionOwner != address(0)) ? stakeData.positionOwner : msg.sender;
        uint256 poolTokenAmount = stakeData.liquidityPoolTokenAmount;
        LiquidityPoolData memory liquidityPoolData;
        // create tokens array
        address[] memory tokens = new address[](2);
        tokens[0] = chosenSetup.mainTokenAddress;
        tokens[1] = stakeData.secondaryTokenAddress;
        if (stakeData.mainTokenAmount > 0 && stakeData.secondaryTokenAmount > 0) {
            // create amounts array
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = stakeData.mainTokenAmount;
            amounts[1] = stakeData.secondaryTokenAmount;
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
            poolTokenAmount = IAMM(chosenSetup.ammPlugin).addLiquidity(liquidityPoolData);
            liquidityPoolData.liquidityPoolAmount = poolTokenAmount;
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
        }
        // retrieve position for the key
        Position storage position = _positions[objectId != 0 ? keccak256(abi.encode(uniqueOwner, objectId, block.number)) : keccak256(abi.encode(uniqueOwner, stakeData.setupIndex, block.number))];
        if (stakeData.mintPositionToken || (position.objectId == 0 && position.uniqueOwner == address(0))) {
            // creating a new position
            _positions[objectId != 0 ? keccak256(abi.encode(uniqueOwner, objectId, block.number)) : keccak256(abi.encode(uniqueOwner, stakeData.setupIndex, block.number))] = Position(
                {
                    objectId: objectId,
                    uniqueOwner: objectId == 0 ? uniqueOwner : address(0),
                    setup: chosenSetup,
                    liquidityPoolData: liquidityPoolData,
                    liquidityPoolTokenAmount: poolTokenAmount,
                    reward: reward,
                    lockedRewardPerBlock: lockedRewardPerBlock,
                    creationBlock: block.number
                }
            );
        }
        if (chosenSetup.free) {
            _rebalanceRewardPerToken(stakeData.setupIndex, poolTokenAmount, false);
        } else {
            _rebalanceRewardPerBlock(lockedRewardPerBlock, false);
        }
        emit NewPosition(objectId != 0 ? keccak256(abi.encode(uniqueOwner, objectId, block.number)) : keccak256(abi.encode(uniqueOwner, stakeData.setupIndex, block.number)));
    }

    /** @dev this function allows a user to withdraw a partial reward.
      * @param objectId owner position token object id.
      * @param setupIndex index of the farming setup.
      * @param creationBlockNumber number of the block when the position was created.
     */
    function partialReward(uint256 objectId, uint256 setupIndex, uint256 creationBlockNumber) public {
        // check if wallet is withdrawing using a position token
        bool hasPositionItem = objectId != 0;
        // create position key
        bytes32 positionKey = hasPositionItem ? keccak256(abi.encode(msg.sender, objectId, creationBlockNumber)) : keccak256(abi.encode(msg.sender, setupIndex, creationBlockNumber));
        // retrieve position
        Position storage position = _positions[positionKey];
        // check if position is valid
        require(position.objectId == objectId && position.setup.ammPlugin != address(0), "Invalid position.");
        if (hasPositionItem) {
            require(position.objectId != 0 && INativeV1(_positionTokenCollection).balanceOf(position.uniqueOwner, position.objectId) == 1, "Invalid position!");
            // burn the position token
            INativeV1(_positionTokenCollection).burn(position.objectId, 1);
        }
        if (!position.setup.free) {
            // check if reward is available
            require(position.reward > 0, "No reward!");
            // calculate the reward from the position creation block to the current block multiplied by the reward per block
            uint256 reward = (block.number >= position.setup.endBlock) ? position.reward : (block.number.sub(position.creationBlock)).mul(position.lockedRewardPerBlock);
            require(reward <= position.reward, "Reward is bigger than expected!");
            // remove the partial reward from the position total reward
            position.reward = position.reward.sub(reward);
            // withdraw the values using the helper
            _withdrawHelper(positionKey, position, setupIndex, false, reward, true);
        } else {
            // withdraw the values
            _withdrawHelper(positionKey, position, setupIndex, false, _calculateFreeFarmingSetupReward(setupIndex, positionKey), true);
            // update the position creation block to exclude all the rewarded blocks
            position.creationBlock = block.number;
        }
    }

    /** @dev this function allows a owner to unlock its position using its position token or not.
      * @param objectId owner position token object id.
      * @param setupIndex index of the farming setup.
      * @param creationBlockNumber number of the block when the position was created.
      * @param unwrapPair if the caller wants to unwrap his pair from the liquidity pool token or not.
      */
    function unlock(uint256 objectId, uint256 setupIndex, uint256 creationBlockNumber, bool unwrapPair) public {
        // check if wallet is withdrawing using a position token
        bool hasPositionItem = objectId != 0;
        // create position key
        bytes32 positionKey = hasPositionItem ? keccak256(abi.encode(msg.sender, objectId, creationBlockNumber)) : keccak256(abi.encode(msg.sender, setupIndex, creationBlockNumber));
        // retrieve position
        Position memory position = _positions[positionKey];
        // check if position is valid
        require(position.objectId == objectId && position.setup.ammPlugin != address(0), "Invalid position.");
        require(position.setup.free || position.setup.endBlock <= block.number, "Invalid unlock!");
        require(!_positionRedeemed[positionKey], "Position already redeemed!");
        hasPositionItem ? _burnPosition(positionKey, msg.sender, position, setupIndex, unwrapPair, false) : _withdraw(positionKey, position, setupIndex, unwrapPair, false);
        _positionRedeemed[positionKey] = true;
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
            if (position.creationBlock <= _setupUpdateBlocks[setupIndex][i]) {
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
        //TODO: metadata
        (objectId,) = INativeV1(_positionTokenCollection).mint(1, "UNIFI PositionToken", "UPT", "google.com", false);
        INativeV1(_positionTokenCollection).safeTransferFrom(address(this), uniqueOwner, objectId, INativeV1(_positionTokenCollection).balanceOf(address(this), objectId), "");
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
        require(position.objectId != 0 && INativeV1(_positionTokenCollection).balanceOf(uniqueOwner, position.objectId) == 1, "Invalid position!");
        // burn the position token
        INativeV1(_positionTokenCollection).burn(position.objectId, 1);
        // withdraw the position
        _withdraw(positionKey, position, setupIndex, unwrapPair, isPartial);
    }

    /** @dev allows the wallet to withdraw its position.
      * @param positionKey staking position key.
      * @param position staking position.
      * @param setupIndex index of the farming setup.
      * @param unwrapPair if the caller wants to unwrap his pair from the liquidity pool token or not.
      * @param isPartial if it's a partial withdraw or not.
      */
    function _withdraw(bytes32 positionKey, Position memory position, uint256 setupIndex, bool unwrapPair, bool isPartial) private {
        _withdrawHelper(positionKey, position, setupIndex, unwrapPair, position.reward, isPartial);
    }

    /** @dev withdraw helper method.
      * @param positionKey staking position key.
      * @param position staking position.
      * @param setupIndex index of the farming setup.
      * @param unwrapPair if the caller wants to unwrap his pair from the liquidity pool token or not.
      * @param reward amount to withdraw.
      * @param isPartial if it's a partial withdraw or not.
     */
    function _withdrawHelper(bytes32 positionKey, Position memory position, uint256 setupIndex, bool unwrapPair, uint256 reward, bool isPartial) private {
        // rebalance setup, if free
        if (_farmingSetups[setupIndex].free) {
            _rebalanceRewardPerToken(setupIndex, position.liquidityPoolTokenAmount, true);
            reward = (reward == 0) ? _calculateFreeFarmingSetupReward(setupIndex, positionKey) : reward;
        }
        // transfer the reward
        if (reward > 0) {
            if (_byMint) {
                IERC20Mintable(_rewardTokenAddress).mint(position.uniqueOwner, reward);
            } else {
                _safeTransferFrom(_rewardTokenAddress, _owner, position.uniqueOwner, reward);
            }
        }
        if (!isPartial) {
            // pay the fees!
            uint256 fee = position.liquidityPoolTokenAmount.mul(_exitFee.mul(1e18).div(100)).div(1e18);
            if (_exitFee > 0) {
                _safeTransfer(position.setup.liquidityPoolTokenAddress, _owner, fee);
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
                _safeTransfer(position.setup.liquidityPoolTokenAddress, position.uniqueOwner, position.liquidityPoolTokenAmount.sub(fee));
            }
            // rebalance the setup if not free
            if (!_farmingSetups[setupIndex].free) {
                _rebalanceRewardPerBlock(position.lockedRewardPerBlock, true);
            }
        }
    }

    /** @dev function used to rebalance the reward per block in the pinned free farming setup.
      * @param lockedRewardPerBlock new position locked reward per block that must be subtracted from the pinned free farming setup reward per block.
      * @param fromExit if the rebalance is caused by an exit from the locked position or not.
      */
    function _rebalanceRewardPerBlock(uint256 lockedRewardPerBlock, bool fromExit) private {
        FarmingSetup storage setup = _farmingSetups[_pinnedSetupIndex];
        fromExit ? setup.rewardPerBlock += lockedRewardPerBlock : setup.rewardPerBlock -= lockedRewardPerBlock;
        _rebalanceRewardPerToken(_pinnedSetupIndex, 0, fromExit);
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

    function getPosition(bytes32 key) public view returns(Position memory) {
        return _positions[key];
    }

    function getRewardPerToken(uint256 setupIndex, uint256 blockNumber) public view returns(uint256) {
        return _rewardPerTokenPerSetupPerBlock[setupIndex][blockNumber];
    }
}