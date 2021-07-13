//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./IFarmMainRegular.sol";
import "./IFarmExtensionRegular.sol";
import "./IFarmFactory.sol";
import "./util/IERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol";

contract FarmMainRegular is IFarmMainRegular {

    // percentage
    uint256 public override constant ONE_HUNDRED = 1e18;
    // event that tracks contracts deployed for the given reward token
    event RewardToken(address indexed rewardTokenAddress);
    // new or transferred farming position event
    event Transfer(uint256 indexed positionId, address indexed from, address indexed to);
    // event that tracks involved tokens for this contract
    event SetupToken(address indexed mainToken, address indexed involvedToken);
    // factory address that will create clones of this contract
    address public _factory;
    // address of the extension of this contract
    address public _extension;
    // address of the reward token
    address public override _rewardTokenAddress;
    // address of the NonfungblePositionManager used for gen2
    INonfungiblePositionManager public nonfungiblePositionManager;
    // mapping containing all the currently available farming setups info
    mapping(uint256 => FarmingSetupInfo) private _setupsInfo;
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
    // mapping containing all the number of opened positions for each setups
    mapping(uint256 => uint256) private _setupPositionsCount;
    // mapping containing all the reward received/paid per setup
    mapping(uint256 => uint256) public _rewardReceived;
    mapping(uint256 => uint256) public _rewardPaid;

    address private _WETH;

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

    /** @dev activeSetupOnly modifier used to check for function calls only if the setup is active. */
    modifier activeSetupOnly(uint256 setupIndex) {
        require(_setups[setupIndex].active, "Setup not active");
        require(_setups[setupIndex].startBlock <= block.number && _setups[setupIndex].endBlock > block.number, "Invalid setup");
        _;
    }

    receive() external payable {}

    /** Extension methods */

    /** @dev initializes the farming contract.
      * @param extension extension address.
      * @param extensionInitData lm extension init payload.
      * @param uniswapV3NonfungiblePositionManager Uniswap V3 Nonfungible Position Manager address.
      * @param rewardTokenAddress address of the reward token.
      * @param farmingSetupInfosBytes optional initial farming Setup Info
      * @return extensionReturnCall result of the extension initialization function, if it was called.
     */
    function init(address extension, bytes memory extensionInitData, address uniswapV3NonfungiblePositionManager, address rewardTokenAddress, bytes memory farmingSetupInfosBytes) public returns(bytes memory extensionReturnCall) {
        require(_factory == address(0), "Already initialized");
        require((_extension = extension) != address(0), "extension");
        _factory = msg.sender;
        emit RewardToken(_rewardTokenAddress = rewardTokenAddress);
        if (keccak256(extensionInitData) != keccak256("")) {
            extensionReturnCall = _call(_extension, extensionInitData);
        }
        _WETH = (nonfungiblePositionManager = INonfungiblePositionManager(uniswapV3NonfungiblePositionManager)).WETH9();
        if(farmingSetupInfosBytes.length > 0) {
            FarmingSetupInfo[] memory farmingSetupInfos = abi.decode(farmingSetupInfosBytes, (FarmingSetupInfo[]));
            for(uint256 i = 0; i < farmingSetupInfos.length; i++) {
                _setOrAddFarmingSetupInfo(farmingSetupInfos[i], true, false, 0);
            }
        }
    }

    function setFarmingSetups(FarmingSetupConfiguration[] memory farmingSetups) public override byExtension {
        for (uint256 i = 0; i < farmingSetups.length; i++) {
            _setOrAddFarmingSetupInfo(farmingSetups[i].info, farmingSetups[i].add, farmingSetups[i].disable, farmingSetups[i].index);
        }
    }

    function finalFlush(address[] calldata tokens, uint256[] calldata amounts) public {
        for(uint256 i = 0; i < _farmingSetupsCount; i++) {
            require(_setupPositionsCount[i] == 0 && !_setups[i].active && _setups[i].totalSupply == 0, "Not Empty");
        }
        (,,, address receiver,) = IFarmExtensionRegular(_extension).data();
        require(tokens.length == amounts.length, "length");
        for(uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amount = amounts[i];
            require(receiver != address(0));
            if(token == address(0)) {
                (bool result,) = receiver.call{value : amount}("");
                require(result, "ETH");
            } else {
                _safeTransfer(token, receiver, amount);
            }
        }
    }

    /** Public methods */

    /** @dev returns the position with the given id.
      * @param positionId id of the position.
      * @return farming position with the given id.
     */
    function position(uint256 positionId) public override view returns (FarmingPosition memory) {
        return _positions[positionId];
    }

    function setup(uint256 setupIndex) public override view returns (FarmingSetup memory, FarmingSetupInfo memory) {
        return (_setups[setupIndex], _setupsInfo[_setups[setupIndex].infoIndex]);
    }

    function setups() public override view returns (FarmingSetup[] memory) {
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

    function toggleSetup(uint256 setupInfoIndex) public {
        uint256 setupIndex = _setupsInfo[setupInfoIndex].lastSetupIndex;
        require(_setups[setupIndex].active && block.number > _setups[setupIndex].endBlock, "Invalid toggle.");
        _toggleSetup(setupIndex);
        _tryClearSetup(setupIndex);
    }

    function openPosition(FarmingPositionRequest memory request) public override payable returns(uint256 positionId) {
        if(!_setups[request.setupIndex].active) {
            activateSetup(_setups[request.setupIndex].infoIndex);
        }
        require(_setups[request.setupIndex].active, "Setup not active");
        require(_setups[request.setupIndex].startBlock <= block.number && _setups[request.setupIndex].endBlock > block.number, "Invalid setup");
        // retrieve the unique owner
        address uniqueOwner = (request.positionOwner != address(0)) ? request.positionOwner : msg.sender;
        // create the position id
        positionId = uint256(keccak256(abi.encode(uniqueOwner, request.setupIndex)));
        require(_positions[positionId].creationBlock == 0, "Invalid open");
        (uint256 tokenId, uint128 liquidityAmount) = _addLiquidity(request.setupIndex, request, 0);
        _updateFreeSetup(request.setupIndex, liquidityAmount, positionId, false);
        _positions[positionId] = FarmingPosition({
            uniqueOwner: uniqueOwner,
            setupIndex : request.setupIndex,
            tokenId: tokenId,
            reward: 0,
            creationBlock: block.number
        });
        _setupPositionsCount[request.setupIndex] += 1;
        emit Transfer(positionId, address(0), uniqueOwner);
    }

    function addLiquidity(uint256 positionId, FarmingPositionRequest memory request) public override payable activeSetupOnly(request.setupIndex) byPositionOwner(positionId) {
        // retrieve farming position
        FarmingPosition storage farmingPosition = _positions[positionId];
        FarmingSetup storage chosenSetup = _setups[farmingPosition.setupIndex];
        // rebalance the reward per token
        _rewardPerTokenPerSetup[farmingPosition.setupIndex] += (((block.number - chosenSetup.lastUpdateBlock) * chosenSetup.rewardPerBlock) * 1e18) / chosenSetup.totalSupply;
        farmingPosition.reward = calculateFreeFarmingReward(positionId, false);
        (, uint128 liquidityAmount) = _addLiquidity(farmingPosition.setupIndex, request, farmingPosition.tokenId);
        _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[farmingPosition.setupIndex];
        // update the last block update variablex
        chosenSetup.lastUpdateBlock = block.number;
        chosenSetup.totalSupply += liquidityAmount;
    }


    /** @dev this function allows a user to withdraw the reward.
      * @param positionId farming position id.
     */
    function withdrawReward(uint256 positionId) external byPositionOwner(positionId) {
        _withdrawReward(positionId, 0, 0, 0);
    }

    function _withdrawReward(uint256 positionId, uint128 liquidityToRemove, uint256 amount0Min, uint256 amount1Min) private {
        // retrieve farming position
        FarmingPosition storage farmingPosition = _positions[positionId];
        FarmingSetup storage farmingSetup = _setups[farmingPosition.setupIndex];
        uint256 reward = farmingPosition.reward;
        uint256 currentBlock = block.number;
        // rebalance setup
        currentBlock = currentBlock > farmingSetup.endBlock ? farmingSetup.endBlock : currentBlock;
        _rewardPerTokenPerSetup[farmingPosition.setupIndex] += (((currentBlock - farmingSetup.lastUpdateBlock) * farmingSetup.rewardPerBlock) * 1e18) / farmingSetup.totalSupply;
        reward = calculateFreeFarmingReward(positionId, false);
        _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[farmingPosition.setupIndex];
        farmingPosition.reward = 0;
        // update the last block update variable
        farmingSetup.lastUpdateBlock = currentBlock;
        _safeTransfer(_rewardTokenAddress, farmingPosition.uniqueOwner, reward);

        _retrieveGen2LiquidityAndFees(positionId, farmingPosition.tokenId, farmingPosition.uniqueOwner, liquidityToRemove, amount0Min, amount1Min);

        _rewardPaid[farmingPosition.setupIndex] += reward;
        if (farmingSetup.endBlock <= block.number && farmingSetup.active) {
            _toggleSetup(farmingPosition.setupIndex);
        }
    }

    function withdrawLiquidity(uint256 positionId, uint128 removedLiquidity) byPositionOwner(positionId) public {
        _withdrawLiquidity(positionId, removedLiquidity, 0, 0);
    }

    function withdrawLiquidity(uint256 positionId, uint128 removedLiquidity, uint256 amount0Min, uint256 amount1Min) byPositionOwner(positionId) public {
        _withdrawLiquidity(positionId, removedLiquidity, amount0Min, amount1Min);
    }

    function _withdrawLiquidity(uint256 positionId, uint128 removedLiquidity, uint256 amount0Min, uint256 amount1Min) public {
        // retrieve farming position
        FarmingPosition storage farmingPosition = _positions[positionId];
        uint128 liquidityPoolTokenAmount = _getLiquidityPoolTokenAmount(farmingPosition.tokenId);
        // current owned liquidity
        require(
            farmingPosition.creationBlock != 0 &&
            removedLiquidity <= liquidityPoolTokenAmount &&
            farmingPosition.uniqueOwner == msg.sender,
            "Invalid withdraw"
        );
        _withdrawReward(positionId, removedLiquidity, amount0Min, amount1Min);
        _setups[farmingPosition.setupIndex].totalSupply -= removedLiquidity;
        liquidityPoolTokenAmount -= removedLiquidity;
        // delete the farming position after the withdraw
        if (liquidityPoolTokenAmount == 0) {
            _setupPositionsCount[farmingPosition.setupIndex] -= 1;
            address(nonfungiblePositionManager).call(abi.encodeWithSelector(nonfungiblePositionManager.collect.selector, INonfungiblePositionManager.CollectParams({
                tokenId: farmingPosition.tokenId,
                recipient: farmingPosition.uniqueOwner,
                amount0Max: 0xffffffffffffffffffffffffffffffff,
                amount1Max: 0xffffffffffffffffffffffffffffffff
            })));
            nonfungiblePositionManager.burn(farmingPosition.tokenId);
            _tryClearSetup(farmingPosition.setupIndex);
            delete _positions[positionId];
        }
    }

    function _tryClearSetup(uint256 setupIndex) private {
        if (_setupPositionsCount[setupIndex] == 0 && !_setups[setupIndex].active) {
            delete _setups[setupIndex];
        }
    }

    function calculateFreeFarmingReward(uint256 positionId, bool isExt) public view returns(uint256 reward) {
        FarmingPosition memory farmingPosition = _positions[positionId];
        uint128 liquidityPoolTokenAmount = _getLiquidityPoolTokenAmount(farmingPosition.tokenId);
        reward = ((_rewardPerTokenPerSetup[farmingPosition.setupIndex] - _rewardPerTokenPaid[positionId]) * liquidityPoolTokenAmount) / 1e18;
        if (isExt) {
            uint256 currentBlock = block.number < _setups[farmingPosition.setupIndex].endBlock ? block.number : _setups[farmingPosition.setupIndex].endBlock;
            uint256 lastUpdateBlock = _setups[farmingPosition.setupIndex].lastUpdateBlock < _setups[farmingPosition.setupIndex].startBlock ? _setups[farmingPosition.setupIndex].startBlock : _setups[farmingPosition.setupIndex].lastUpdateBlock;
            uint256 rpt = (((currentBlock - lastUpdateBlock) * _setups[farmingPosition.setupIndex].rewardPerBlock) * 1e18) / _setups[farmingPosition.setupIndex].totalSupply;
            reward += (rpt * liquidityPoolTokenAmount) / 1e18;
        }
        reward += farmingPosition.reward;
    }

    /** Private methods */

    function _getLiquidityPoolTokenAmount(uint256 tokenId) private view returns (uint128 liquidityAmount){
        (,,,,,,,liquidityAmount,,,,) = nonfungiblePositionManager.positions(tokenId);
    } 

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
                farmingSetupInfo.liquidityPoolTokenAddress != address(0) &&
                farmingSetupInfo.originalRewardPerBlock > 0,
                "Invalid setup configuration"
            );
            _checkTicks(farmingSetupInfo.tickLower, farmingSetupInfo.tickUpper);
            address[] memory tokenAddresses = new address[](2);
            tokenAddresses[0] = IUniswapV3Pool(info.liquidityPoolTokenAddress).token0();
            tokenAddresses[1] = IUniswapV3Pool(info.liquidityPoolTokenAddress).token1();
            bool mainTokenFound = false;
            bool ethTokenFound = false;
            for(uint256 z = 0; z < tokenAddresses.length; z++) {
                if(tokenAddresses[z] == _WETH) {
                    ethTokenFound = true;
                }
                if(tokenAddresses[z] == farmingSetupInfo.mainTokenAddress) {
                    mainTokenFound = true;
                } else {
                    emit SetupToken(farmingSetupInfo.mainTokenAddress, tokenAddresses[z]);
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

        if (setup.active) {
            setup = _setups[setupIndex];
            if(block.number < setup.endBlock) {
                uint256 difference = info.originalRewardPerBlock < farmingSetupInfo.originalRewardPerBlock ? farmingSetupInfo.originalRewardPerBlock - info.originalRewardPerBlock : info.originalRewardPerBlock - farmingSetupInfo.originalRewardPerBlock;
                uint256 duration = setup.endBlock - block.number;
                uint256 amount = difference * duration;
                if (amount > 0) {
                    if (info.originalRewardPerBlock > farmingSetupInfo.originalRewardPerBlock) {
                        require(_ensureTransfer(amount), "Insufficient reward in extension.");
                        _rewardReceived[setupIndex] += amount;
                    }
                    _updateFreeSetup(setupIndex, 0, 0, false);
                    setup.rewardPerBlock = info.originalRewardPerBlock;
                }
            }
            _setupsInfo[_setups[setupIndex].infoIndex].originalRewardPerBlock = info.originalRewardPerBlock;
        }
        if(_setupsInfo[_setups[setupIndex].infoIndex].renewTimes > 0) {
            _setupsInfo[_setups[setupIndex].infoIndex].renewTimes = info.renewTimes;
        }
    }

    function _transferToMeAndCheckAllowance(FarmingSetup memory setup, FarmingPositionRequest memory request) private {
        address[] memory tokens = new address[](2);
        tokens[0] = IUniswapV3Pool(_setupsInfo[setup.infoIndex].liquidityPoolTokenAddress).token0();
        tokens[1] = IUniswapV3Pool(_setupsInfo[setup.infoIndex].liquidityPoolTokenAddress).token1();
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = request.amount0;
        tokenAmounts[1] = request.amount1;
        require((_setupsInfo[setup.infoIndex].mainTokenAddress == tokens[0] ? tokenAmounts[0] : tokenAmounts[1]) >= _setupsInfo[setup.infoIndex].minStakeable, "Invalid liquidity.");
        // iterate the tokens and perform the transferFrom and the approve
        for(uint256 i = 0; i < tokens.length; i++) {
            if(_setupsInfo[setup.infoIndex].involvingETH && _WETH == tokens[i]) {
                require(msg.value == tokenAmounts[i], "Incorrect eth value");
            } else {
                _safeTransferFrom(tokens[i], msg.sender, address(this), tokenAmounts[i]);
                _safeApprove(tokens[i], address(nonfungiblePositionManager), tokenAmounts[i]);
            }
        }
    }

    /// @dev addliquidity only for gen2
    function _addLiquidity(uint256 setupIndex, FarmingPositionRequest memory request, uint256 tokenIdInput) private returns(uint256 tokenId, uint128 liquidityAmount) {
        tokenId = tokenIdInput;
        _transferToMeAndCheckAllowance(_setups[setupIndex], request);

        FarmingSetupInfo memory setupInfo = _setupsInfo[_setups[setupIndex].infoIndex];
        bytes[] memory data = new bytes[](setupInfo.involvingETH ? 2 : 1);

        address token0 = IUniswapV3Pool(setupInfo.liquidityPoolTokenAddress).token0();
        address token1 = IUniswapV3Pool(setupInfo.liquidityPoolTokenAddress).token1();
        uint256 ethValue = setupInfo.involvingETH ? token0 == _WETH ? request.amount0 : request.amount1 : 0;
        uint256 amount0;
        uint256 amount1;

        if(setupInfo.involvingETH) {
            data[1] = abi.encodeWithSelector(nonfungiblePositionManager.refundETH.selector);
        }
        if(tokenId == 0) {
            data[0] = abi.encodeWithSelector(nonfungiblePositionManager.mint.selector, INonfungiblePositionManager.MintParams({
                token0: token0, 
                token1: token1,
                fee: IUniswapV3Pool(setupInfo.liquidityPoolTokenAddress).fee(),
                tickLower: setupInfo.tickLower, 
                tickUpper: setupInfo.tickUpper,
                amount0Desired: request.amount0, 
                amount1Desired: request.amount1,
                amount0Min: request.amount0Min,
                amount1Min: request.amount1Min,
                recipient: address(this),
                deadline: block.timestamp + 10000
            }));
            (tokenId, liquidityAmount, amount0, amount1) = abi.decode(IMulticall(address(nonfungiblePositionManager)).multicall{ value: ethValue }(data)[0], (uint256, uint128, uint256, uint256));
        } else {
            data[0] = abi.encodeWithSelector(nonfungiblePositionManager.increaseLiquidity.selector, INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId, 
                amount0Desired: request.amount0, 
                amount1Desired: request.amount1,
                amount0Min: request.amount0Min,
                amount1Min: request.amount1Min,
                deadline: block.timestamp + 10000
            }));
            (liquidityAmount, amount0, amount1) = abi.decode(IMulticall(address(nonfungiblePositionManager)).multicall{ value : ethValue }(data)[0], (uint128, uint256, uint256));
        }

        if(amount0 < request.amount0){
            _safeTransfer(setupInfo.involvingETH && token0 == _WETH ? address(0) : token0, msg.sender, request.amount0 - amount0);
        }

        if(amount1 < request.amount1){
            _safeTransfer(setupInfo.involvingETH && token1 == _WETH ? address(0) : token1, msg.sender, request.amount1 - amount1);
        }
    }

    /** @dev updates the free setup with the given index.
      * @param setupIndex index of the setup that we're updating.
      * @param amount amount of liquidity that we're adding/removeing.
      * @param positionId position id.
      * @param fromExit if it's from an exit or not.
     */
    function _updateFreeSetup(uint256 setupIndex, uint128 amount, uint256 positionId, bool fromExit) private {
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

        require(block.number > _setupsInfo[setup.infoIndex].startBlock, "Too early for this setup");

        if (setup.active && block.number >= setup.endBlock && _setupsInfo[setup.infoIndex].renewTimes == 0) {
            setup.active = false;
            return;
        } else if (block.number >= setup.startBlock && block.number < setup.endBlock && setup.active) {
            setup.active = false;
            _setupsInfo[setup.infoIndex].renewTimes = 0;
            uint256 amount = (setup.endBlock - block.number) * setup.rewardPerBlock;
            setup.endBlock = block.number;
            _updateFreeSetup(setupIndex, 0, 0, false);
            _rewardReceived[setupIndex] -= amount;
            _giveBack(amount);
            return;
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
            _setups[_farmingSetupsCount].deprecatedObjectId = 0;
            _setups[_farmingSetupsCount].totalSupply = 0;
            _farmingSetupsCount += 1;
        } else if (setup.active && !wasActive) {
            _rewardReceived[setupIndex] = setup.rewardPerBlock * _setupsInfo[_setups[setupIndex].infoIndex].blockDuration;
            // update new setup
            _setups[setupIndex].startBlock = block.number;
            _setups[setupIndex].endBlock = block.number + _setupsInfo[_setups[setupIndex].infoIndex].blockDuration;
            _setups[setupIndex].totalSupply = 0;
            _setupsInfo[_setups[setupIndex].infoIndex].renewTimes -= 1;
        } else {
            _setupsInfo[_setups[setupIndex].infoIndex].renewTimes = 0;
        }
    }

    /** @dev function used to safely approve ERC20 transfers.
      * @param erc20TokenAddress address of the token to approve.
      * @param to receiver of the approval.
      * @param value amount to approve for.
     */
    function _safeApprove(address erc20TokenAddress, address to, uint256 value) internal virtual {
        if(value == 0) {
            return;
        }
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).approve.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'APPROVE_FAILED');
    }

    /** @dev function used to safe transfer ERC20 tokens.
      * @param erc20TokenAddress address of the token to transfer.
      * @param to receiver of the tokens.
      * @param value amount of tokens to transfer.
     */
    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) internal virtual {
        if(value == 0) {
            return;
        }
        if(erc20TokenAddress == address(0)) {
            (bool result,) = to.call{value : value}("");
            require(result, "TRANSFER_FAILED");
            return;
        }
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
        if(value == 0) {
            return;
        }
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

    /** @dev gives back the reward to the extension.
      * @param amount to give back.
     */
    function _giveBack(uint256 amount) private {
        if(amount == 0) {
            return;
        }
        if (_rewardTokenAddress == address(0)) {
            IFarmExtensionRegular(_extension).backToYou{value : amount}(amount);
        } else {
            _safeApprove(_rewardTokenAddress, _extension, amount);
            IFarmExtensionRegular(_extension).backToYou(amount);
        }
    }

    /** @dev ensures the transfer from the contract to the extension.
      * @param amount amount to transfer.
     */
    function _ensureTransfer(uint256 amount) private returns(bool) {
        uint256 initialBalance = _rewardTokenAddress == address(0) ? address(this).balance : IERC20(_rewardTokenAddress).balanceOf(address(this));
        uint256 expectedBalance = initialBalance + amount;
        try IFarmExtensionRegular(_extension).transferTo(amount) {} catch {}
        uint256 actualBalance = _rewardTokenAddress == address(0) ? address(this).balance : IERC20(_rewardTokenAddress).balanceOf(address(this));
        if(actualBalance == expectedBalance) {
            return true;
        }
        _giveBack(actualBalance - initialBalance);
        return false;
    }

    /// @dev Common checks for valid tick inputs.
    function _checkTicks(int24 tickLower, int24 tickUpper) private pure {
        require(tickLower < tickUpper, 'TLU');
        require(tickLower >= TickMath.MIN_TICK, 'TLM');
        require(tickUpper <= TickMath.MAX_TICK, 'TUM');
    }

    // only called from gen2 code
    function _retrieveGen2LiquidityAndFees(uint256 positionId, uint256 tokenId, address recipient, uint128 liquidityToRemove, uint256 amount0Min, uint256 amount1Min) private {
        uint256 decreasedAmount0 = 0;
        uint256 decreasedAmount1 = 0;

        if(liquidityToRemove > 0) {
            (decreasedAmount0, decreasedAmount1) = nonfungiblePositionManager.decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams(
                tokenId,
                liquidityToRemove,
                amount0Min,
                amount1Min,
                block.timestamp + 10000
            ));
        }

        address token0;
        address token1;
        uint256 collectedAmount0;
        uint256 collectedAmount1;
        (token0, token1, collectedAmount0, collectedAmount1) = _collect(positionId, tokenId);
        (uint256 exitFeePercentage, address exitFeeWallet) = IFarmFactory(_factory).feePercentageInfo();
        (uint256 dfoFee0, uint256 dfoFee1) = (0, 0);
        if (exitFeePercentage > 0) {
            dfoFee0 = ((collectedAmount0 - decreasedAmount0) * ((exitFeePercentage * 1e18) / ONE_HUNDRED)) / 1e18;
            dfoFee1 = ((collectedAmount1 - decreasedAmount1) * ((exitFeePercentage * 1e18) / ONE_HUNDRED)) / 1e18;
            _safeTransfer(token0, exitFeeWallet, dfoFee0);
            _safeTransfer(token1, exitFeeWallet, dfoFee1);
        }
        _safeTransfer(token0, recipient, collectedAmount0 - dfoFee0);
        _safeTransfer(token1, recipient, collectedAmount1 - dfoFee1);
    }

    function _collect(uint256 positionId, uint256 tokenId) private returns (address token0, address token1, uint256 amount0, uint256 amount1) {
        bool involvingETH = _setupsInfo[_setups[_positions[positionId].setupIndex].infoIndex].involvingETH;
        bytes[] memory data = new bytes[](involvingETH ? 3 : 1);
        data[0] = abi.encodeWithSelector(nonfungiblePositionManager.collect.selector, INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: involvingETH ? address(0) : address(this),
            amount0Max: 0xffffffffffffffffffffffffffffffff,
            amount1Max: 0xffffffffffffffffffffffffffffffff
        }));
        (,, token0, token1, , , , , , , , ) = nonfungiblePositionManager.positions(tokenId);
        if(involvingETH) {
            data[1] = abi.encodeWithSelector(nonfungiblePositionManager.unwrapWETH9.selector, 0, address(this));
            data[2] = abi.encodeWithSelector(nonfungiblePositionManager.sweepToken.selector, token0 == _WETH ? token1 : token0, 0, address(this));
            token0 = token0 == _WETH ? address(0) : token0;
            token1 = token1 == _WETH ? address(0) : token1;
        }
        (amount0, amount1) = abi.decode(IMulticall(address(nonfungiblePositionManager)).multicall(data)[0], (uint256, uint256));
    }
}