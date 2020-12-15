//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../amm-aggregator/common/AMMData.sol";
import "../amm-aggregator/common/IAMM.sol";
import "./util/IERC20.sol";
import "./util/IEthItemOrchestrator.sol";
import "./util/INativeV1.sol";
import "./util/SafeMath.sol";

contract LiquidityMining {
    // SafeMath library
    using SafeMath for uint256;

    // farming setup struct
    struct FarmingSetup {
        address ammPlugin; // amm plugin address used for this setup (eg. uniswap amm plugin address).
        address liquidityPoolTokenAddress; // address of the liquidity pool token
        uint256 startBlock; // farming setup start block (valid only if free is false).
        uint256 endBlock; // farming setup end block (valid only if free is false).
        uint256 rewardPerBlock; // farming setup reward per single block.
        uint256 maximumLiquidity; // maximum total liquidity
        uint256 startingReward; // farming setup starting total reward.
        address mainTokenAddress; // eg. buidl address.
        address[] secondaryTokenAddresses; // eg. [address(0), dai address].
        bool free; // if the setup is a free farming setup or a locked one.
        bool pinned; // if the setups is free and pinned then it's involved in the load balancing process.
    }

    // position struct
    struct Position {
        uint256 objectId; // object id representing the position token if minted, 0 if uniqueOwner is populated.
        address uniqueOwner; // address representing the owner address, address(0) if objectId is populated.
        FarmingSetup setup; // chosen setup when the position was created.
        LiquidityProviderData[] liquidityProviderDataArray; // array of amm liquidity provider data.
        uint256 reward; // position reward.
        uint256 creationBlock; // block when this position was created.
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
    FarmingSetup[] private _farmingSetups;
    // mapping containing all the positions
    mapping(bytes32 => Position) private _positions;
    // owner exit fee
    uint256 private _exitFee;

    /** @dev creates the first instance of this contract that will be cloned from the _factory contract.
      * @param _factory address of the factory contract.
     */
    constructor(address _factory) {
        FACTORY = _factory;
    }

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
      * @param farmingSetups array containing all initial farming setups.
      * @return success if the initialize function has ended properly.
     */
    function initialize(address owner, bytes memory ownerInitData, address orchestrator, string memory name, string memory symbol, string memory collectionUri, address rewardTokenAddress, bool byMint, FarmingSetup[] memory farmingSetups) public onlyFactory returns(bool) {
        require(
            _owner == address(0) && 
            _rewardTokenAddress == address(0),
            "Already initialized."
        );
        _owner = owner;
        _rewardTokenAddress = rewardTokenAddress;
        (_positionTokenCollection,) = IEthItemOrchestrator(orchestrator).createNative(abi.encodeWithSignature("init(string,string,bool,string,address,bytes)", name, symbol, true, collectionUri, address(this), ""), "");
        _byMint = byMint;
        _farmingSetups = farmingSetups;
        if (keccak256(ownerInitData) != keccak256("")) {
            (bool result,) = _owner.call(ownerInitData);
            require(result, "Error while initializing owner.");
        }
        return true;
    }

    /** @dev function called by the owner to add or update an existing setup.
      * @param setupIndex index of the setup to replace or any number > than the setups length to add a new one.
      * @param setup new or updated setup.
     */
    function addOrUpdateFarmingSetup(uint256 setupIndex, FarmingSetup memory setup) public onlyOwner {
        if (setupIndex > _farmingSetups.length) {
            // we are creating a new setup
            require(!setup.free ? setup.startBlock > block.number && setup.endBlock > setup.startBlock : true, "Invalid setup.");
            _farmingSetups[_farmingSetups.length - 1] = setup;
        } else {
            // we are updating an existing setup
            FarmingSetup memory existingSetup = _farmingSetups[setupIndex];
            if (!existingSetup.free) {
                // updating a locked FarmingSetup
                require(existingSetup.endBlock < block.number && setup.endBlock > setup.startBlock && setup.startBlock > block.number, "Setup still active.");
                existingSetup = setup;
            } else {
                // updating a free FarmingSetup
                existingSetup.rewardPerBlock = setup.rewardPerBlock;
            }
        }
    }

    /** Public methods. */

    /** @dev function called by external users to open a new position. 
      * @param setupIndex index of the chosen setup.
      * @param secondaryTokenAddress address of the chosen secondary token (must be inside the setup list).
      * @param liquidityPoolTokenAmount amount of liquidity pool token.
      * @param mainTokenAmount amount of the main token to stake.
      * @param secondaryTokenAmount amount of the secondary token to stake.
      * @param positionOwner position owner address or address(0) (in this case msg.sender is used).
      * @param mintPositionToken true if the sender wants the position tokens or not.
    */
    function stake(uint256 setupIndex, address secondaryTokenAddress, uint256 liquidityPoolTokenAmount, uint256 mainTokenAmount, uint256 secondaryTokenAmount, address positionOwner, bool mintPositionToken) public {
        require(setupIndex < _farmingSetups.length, "Invalid setup index.");
        // retrieve the setup
        FarmingSetup storage chosenSetup = _farmingSetups[setupIndex];
        require(_isAcceptedToken(chosenSetup.secondaryTokenAddresses, secondaryTokenAddress), "Invalid secondary token.");
        // retrieve the unique owner
        address uniqueOwner = (positionOwner != address(0)) ? positionOwner : msg.sender;
        // retrieve the IAMM
        IAMM amm = IAMM(chosenSetup.ammPlugin);
        // create tokens array
        address[] memory tokens;
        tokens[0] = chosenSetup.mainTokenAddress;
        tokens[1] = secondaryTokenAddress;
        // create amounts array
        uint256[] memory amounts;
        amounts[0] = mainTokenAmount;
        amounts[1] = secondaryTokenAmount;
        // create the liquidity provider data
        LiquidityProviderData memory liquidityProviderData = LiquidityProviderData(
            chosenSetup.liquidityPoolTokenAddress, 
            liquidityPoolTokenAmount, 
            tokens, 
            amounts, 
            uniqueOwner, 
            address(this)
        );
        // retrieve the poolTokenAmount from the amm
        uint256 poolTokenAmount = amm.addLiquidity(liquidityProviderData);
        // create the default position key variable
        bytes32 positionKey;
        uint256 objectId;
        if (mintPositionToken) {
            // user wants position token
            objectId = _mintPosition(uniqueOwner); // update 0 with positionToken objectId
            positionKey = keccak256(abi.encode(uniqueOwner, objectId));
        } else {
            // user does not want position token
            positionKey = keccak256(abi.encode(uniqueOwner, setupIndex));
        }
        Position storage position = _positions[positionKey];
        // calculate the reward
        uint256 reward = chosenSetup.free ? 0 : _calculateLockedFarmingSetupReward(setupIndex, mainTokenAmount);
        if (mintPositionToken || (position.objectId == 0 && position.uniqueOwner == address(0))) {
            // creating a new position
            LiquidityProviderData[] memory liquidityProviderDataArray;
            liquidityProviderDataArray[0] = liquidityProviderData;
            _positions[positionKey] = Position(
                { 
                    objectId: objectId, 
                    uniqueOwner: objectId != 0 ? uniqueOwner : address(0), 
                    setup: chosenSetup, 
                    liquidityProviderDataArray: liquidityProviderDataArray,
                    reward: reward, 
                    creationBlock: block.number
                }
            );
        } else {
            // updating existing position
            position.reward += reward;
            position.liquidityProviderDataArray.push(liquidityProviderData);
        }
    }


    function unlock(uint256 objectId, uint256 setupIndex) public {
        // check if wallet is withdrawing using a position token 
        bool hasPositionItem = objectId != 0;
        // create position key
        bytes32 positionKey = hasPositionItem ? keccak256(abi.encode(msg.sender, objectId)) : keccak256(abi.encode(msg.sender, setupIndex));
        // retrieve position
        Position memory position = _positions[positionKey];
        // check if position is valid
        require(position.objectId == objectId && position.setup.ammPlugin != address(0), "Invalid position.");
        require(position.setup.free && _farmingSetups[setupIndex].free, "Setup has changed!");
        require(!position.setup.free && position.setup.startBlock <= block.number && position.setup.endBlock >= block.number, "Not withrawable yet!");
        hasPositionItem ? _burnPosition(position) : _withdraw(position);
    }
    
    /** Private methods. */

    /** @dev function used to calculate the reward based on the input parameters.
      * @param setupIndex index of the farming setup.
      * @param mainTokenAmount amount of main token used to calculate reward in a locked farming setup.
      * @param poolTokenAmount amount of liquidity pool token used to calculate reward in a free farming setup.
      * @return reward total reward for the position owner.
     */
    function _calculateReward(uint256 setupIndex, uint256 mainTokenAmount, uint256 poolTokenAmount) private returns(uint256 reward) {
        reward = _farmingSetups[setupIndex].free ? _calculateFreeFarmingSetupReward(setupIndex, poolTokenAmount) : _calculateLockedFarmingSetupReward(setupIndex, mainTokenAmount);
    }

    /** @dev function used to calculate the reward in a free farming setup.
      * @param setupIndex index of the farming setup.
      * @param poolTokenAmount amount of liquidity pool token.
      * @return reward total reward for the position owner.
     */
    function _calculateFreeFarmingSetupReward(uint256 setupIndex, uint256 poolTokenAmount) private returns(uint256 reward) {}

    /** @dev function used to calculate the reward in a locked farming setup.
      * @param setupIndex index of the farming setup.
      * @param mainTokenAmount amount of main token.
      * @return reward total reward for the position owner.
     */
    function _calculateLockedFarmingSetupReward(uint256 setupIndex, uint256 mainTokenAmount) private returns(uint256 reward) {
        FarmingSetup storage setup = _farmingSetups[setupIndex];
        uint256 remainingBlocks = setup.endBlock.sub(block.number);
        require(remainingBlocks > 0, "Setup ended!");
        uint256 totalStillAvailable = setup.rewardPerBlock.mul(remainingBlocks);
        require(totalStillAvailable > 0, "No rewards!");
        uint256 relativeLiquidity = mainTokenAmount.div(setup.startingReward);
        uint256 relativeRewardPerBlock = relativeLiquidity.mul(setup.rewardPerBlock);
        reward = relativeRewardPerBlock * remainingBlocks;
        require(reward <= totalStillAvailable, "No availability.");
        setup.rewardPerBlock -= relativeRewardPerBlock;
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
        (objectId,) = INativeV1(_positionTokenCollection).mint(1, "UNIFI PositionToken", "UPT", "", false);
        INativeV1(_positionTokenCollection).safeTransferFrom(address(this), uniqueOwner, objectId, INativeV1(_positionTokenCollection).balanceOf(address(this), objectId), "");
    }

    /** @dev burns a PositionToken from the collection.
      * @param objectId position token object id.
      * @param position
      */
    function _burnPosition(Position memory position) private {
        require(position.objectId != 0, "Invalid position!");
        // burn the position token
        INativeV1(_positionTokenCollection).burn(position.objectId, 1);
        _withdraw(position);
    }

    /** @dev allows the wallet to withdraw its position.
      * @param position staking position.
      */
    function _withdraw(Position memory position) private {
        // transfer the reward
        if (!position.setup.free && position.reward > 0) {
            IERC20(_rewardTokenAddress).transfer(position.uniqueOwner, position.reward);
        }
        // remove liquidity using AMM
        IAMM(position.setup.ammPlugin).removeLiquidityBatch(position.liquidityProviderDataArray);
    }
}