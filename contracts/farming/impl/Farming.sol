//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/IFarmingExtension.sol";
import "@ethereansos/swissknife/contracts/generic/impl/LazyInitCapableElement.sol";
import "../../amm-aggregator/model/IAMM.sol";
import { IERC20Full as IERC20 } from "@ethereansos/swissknife/contracts/lib/GeneralUtilities.sol";

contract Farming is IFarming, LazyInitCapableElement {

    uint256 private constant ONE_HUNDRED = 1e18;
    uint256 private constant TIME_SLOTS_IN_SECONDS = 15;

    address private _ammAggregatorAddress;

    address public override rewardTokenAddress;

    uint256 private _farmingSetupsInfoCount;
    mapping(uint256 => FarmingSetupInfo) private _setupsInfo;

    uint256 private _farmingSetupsCount;
    mapping(uint256 => FarmingSetup) private _setups;

    mapping(uint256 => FarmingPosition) private _position;
    // mapping containing the reward per token per setup per event
    mapping(uint256 => uint256) private _rewardPerTokenPerSetup;
    // mapping containing the reward per token paid per _position
    mapping(uint256 => uint256) private _rewardPerTokenPaid;
    // mapping containing whether a farming _position has been partially reedemed or not
    mapping(uint256 => uint256) public _partiallyRedeemed;
    // mapping containing all the number of opened positions for each setups
    mapping(uint256 => uint256) private _setupPositionsCount;
    // mapping containing all the reward received/paid per setup
    mapping(uint256 => uint256) public _rewardReceived;
    mapping(uint256 => uint256) public _rewardPaid;

    constructor(bytes memory lazyInitData) LazyInitCapableElement(lazyInitData) {}

    modifier byExtension() {
        require(msg.sender == host, "Unauthorized");
        _;
    }

    modifier byPositionOwner(uint256 positionId) {
        require(_position[positionId].uniqueOwner == msg.sender && _position[positionId].creationEvent != 0, "Not owned");
        _;
    }

    modifier activeSetupOnly(uint256 setupIndex) {
        require(_setups[setupIndex].active, "Setup not active");
        require(_setups[setupIndex].startEvent <= block.timestamp && _setups[setupIndex].endEvent > block.timestamp, "Invalid setup");
        _;
    }

    receive() external payable {}

    /** Extension methods */

    function lazyInit(bytes memory lazyInitData) external override returns(bytes memory extensionInitResult) {
        address _host = host;
        require(_host != address(0), "host");

        (_ammAggregatorAddress, lazyInitData) = abi.decode(lazyInitData, (address, bytes));

        bytes memory farmingSetupInfosBytes;
        address _rewardTokenAddress;
        (lazyInitData, _rewardTokenAddress, farmingSetupInfosBytes) = abi.decode(lazyInitData, (bytes, address, bytes));

        if(keccak256(lazyInitData) != keccak256("")) {
            extensionInitResult = ILazyInitCapableElement(_host).lazyInit(lazyInitData);
        }

        emit RewardToken(rewardTokenAddress = _rewardTokenAddress);
        if(farmingSetupInfosBytes.length > 0) {
            FarmingSetupInfo[] memory farmingSetupInfos = abi.decode(farmingSetupInfosBytes, (FarmingSetupInfo[]));
            for(uint256 i = 0; i < farmingSetupInfos.length; i++) {
                _setOrAddFarmingSetupInfo(farmingSetupInfos[i], true, false, 0);
            }
        }
    }

    function _supportsInterface(bytes4 selector) internal override view returns(bool) {
    }

    function position(uint256 positionId) external view returns(FarmingPosition memory) {
        return _position[positionId];
    }

    function setFarmingSetups(FarmingSetupConfiguration[] memory farmingSetups) external override byExtension {
        for (uint256 i = 0; i < farmingSetups.length; i++) {
            _setOrAddFarmingSetupInfo(farmingSetups[i].info, farmingSetups[i].add, farmingSetups[i].disable, farmingSetups[i].index);
        }
    }

    function finalFlush(address[] calldata tokens, uint256[] calldata amounts) external  {
        for(uint256 i = 0; i < _farmingSetupsCount; i++) {
            require(_setupPositionsCount[i] == 0 && !_setups[i].active && _setups[i].totalSupply == 0, "Not Empty");
        }
        (,,, address receiver,) = IFarmingExtension(host).data();
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

    function setup(uint256 setupIndex) external override view returns (FarmingSetup memory, FarmingSetupInfo memory) {
        if(setupIndex < _farmingSetupsCount) {
            return (_setups[setupIndex], _setupsInfo[_setups[setupIndex].infoIndex]);
        }
    }

    function setups() external override view returns (FarmingSetup[] memory) {
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

    function toggleSetup(uint256 setupInfoIndex) external {
        require(_setups[_setupsInfo[setupInfoIndex].lastSetupIndex].active && block.timestamp > _setups[_setupsInfo[setupInfoIndex].lastSetupIndex].endEvent, "Invalid toggle.");
        _toggleSetup(_setupsInfo[setupInfoIndex].lastSetupIndex);
    }

    function openPosition(FarmingPositionRequest memory request) external override payable returns(uint256 positionId) {
        if(!_setups[request.setupIndex].active) {
            activateSetup(_setups[request.setupIndex].infoIndex);
        }

        // retrieve the setup
        FarmingSetup storage chosenSetup = _setups[request.setupIndex];
        // retrieve the unique owner
        address uniqueOwner = (request.positionOwner != address(0)) ? request.positionOwner : msg.sender;
        // create the _position id
        positionId = uint256(keccak256(abi.encode(uniqueOwner, _setupsInfo[chosenSetup.infoIndex].free ? 0 : block.timestamp, request.setupIndex)));
        require(_position[positionId].creationEvent == 0, "Invalid open");
        // create the lp data for the amm
        (LiquidityPoolParams memory liquidityPoolData, uint256 mainTokenAmount) = _addLiquidity(request.setupIndex, request);
        // calculate the reward
        uint256 reward;
        uint256 lockedRewardPerEvent;
        require(_setupsInfo[chosenSetup.infoIndex].free, "free");
        _updateFreeSetup(request.setupIndex, liquidityPoolData.amount, positionId, false);
        _position[positionId] = FarmingPosition({
            uniqueOwner: uniqueOwner,
            setupIndex : request.setupIndex,
            liquidityPoolTokenAmount: liquidityPoolData.amount,
            mainTokenAmount: mainTokenAmount,
            reward: reward,
            lockedRewardPerEvent: lockedRewardPerEvent,
            creationEvent: block.timestamp
        });
        _setupPositionsCount[request.setupIndex] += (1 + (_setupsInfo[chosenSetup.infoIndex].free ? 0 : liquidityPoolData.amount));
        emit Transfer(positionId, address(0), uniqueOwner);
    }

    function addLiquidity(uint256 positionId, FarmingPositionRequest memory request) external override payable activeSetupOnly(request.setupIndex) byPositionOwner(positionId) {
        // retrieve farming _position
        FarmingPosition storage farmingPosition = _position[positionId];
        FarmingSetup storage chosenSetup = _setups[farmingPosition.setupIndex];
        // check if farmoing _position is valid
        require(_setupsInfo[chosenSetup.infoIndex].free, "Invalid add liquidity");
        // create the lp data for the amm
        (LiquidityPoolParams memory liquidityPoolData,) = _addLiquidity(farmingPosition.setupIndex, request);
        // rebalance the reward per token
        _rewardPerTokenPerSetup[farmingPosition.setupIndex] += (((block.timestamp - chosenSetup.lastUpdateEvent) * chosenSetup.rewardPerEvent) * 1e18) / chosenSetup.totalSupply;
        farmingPosition.reward = calculateFreeFarmingReward(positionId, false);
        _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[farmingPosition.setupIndex];
        farmingPosition.liquidityPoolTokenAmount += liquidityPoolData.amount;
        // update the last event update variablex
        chosenSetup.lastUpdateEvent = block.timestamp;
        chosenSetup.totalSupply += liquidityPoolData.amount;
    }


    /** @dev this function allows a user to withdraw the reward.
      * @param positionId farming _position id.
     */
    function withdrawReward(uint256 positionId) public byPositionOwner(positionId) {
        // retrieve farming _position
        FarmingPosition storage farmingPosition = _position[positionId];
        uint256 reward = farmingPosition.reward;
        uint256 currentEvent = block.timestamp;

        // rebalance setup
        currentEvent = currentEvent > _setups[farmingPosition.setupIndex].endEvent ? _setups[farmingPosition.setupIndex].endEvent : currentEvent;
        _rewardPerTokenPerSetup[farmingPosition.setupIndex] += (((currentEvent - _setups[farmingPosition.setupIndex].lastUpdateEvent) * _setups[farmingPosition.setupIndex].rewardPerEvent) * 1e18) / _setups[farmingPosition.setupIndex].totalSupply;
        reward = calculateFreeFarmingReward(positionId, false);
        _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[farmingPosition.setupIndex];
        farmingPosition.reward = 0;
        // update the last event update variable
        _setups[farmingPosition.setupIndex].lastUpdateEvent = currentEvent;

        if (reward > 0) {
            // transfer the reward
            if (rewardTokenAddress != address(0)) {
                _safeTransfer(rewardTokenAddress, farmingPosition.uniqueOwner, reward);
            } else {
                (bool result,) = farmingPosition.uniqueOwner.call{value:reward}("");
                require(result, "Invalid ETH transfer.");
            }
            _rewardPaid[farmingPosition.setupIndex] += reward;
        }
        if (_setups[farmingPosition.setupIndex].endEvent <= block.timestamp) {
            if (_setups[farmingPosition.setupIndex].active) {
                _toggleSetup(farmingPosition.setupIndex);
            }
            // close the locked _position after withdrawing all the reward
            if (!_setupsInfo[_setups[farmingPosition.setupIndex].infoIndex].free) {
                _setupPositionsCount[farmingPosition.setupIndex] -= 1;
                if (_setupPositionsCount[farmingPosition.setupIndex] == 0 && !_setups[farmingPosition.setupIndex].active) {
                    delete _setups[farmingPosition.setupIndex];
                }
                delete _position[positionId];
            }
        } else if (!_setupsInfo[_setups[farmingPosition.setupIndex].infoIndex].free) {
            // set the partially redeemed amount
            _partiallyRedeemed[positionId] += reward;
        }
    }

    function withdrawLiquidity(uint256 positionId, uint256 objectId, uint256 removedLiquidity, uint256 amount0Min, uint256 amount1Min, bytes memory burnData) external {
        // retrieve farming _position
        FarmingPosition memory farmingPosition = _position[positionId];
        uint256 setupIndex = farmingPosition.setupIndex;
        require((positionId != 0 && objectId == 0) || (objectId != 0 && positionId == 0 && _setups[setupIndex].objectId == objectId), "Invalid _position");
        // current owned liquidity
        require(
            (
                _setupsInfo[_setups[farmingPosition.setupIndex].infoIndex].free &&
                farmingPosition.creationEvent != 0 &&
                removedLiquidity <= farmingPosition.liquidityPoolTokenAmount &&
                farmingPosition.uniqueOwner == msg.sender &&
                positionId != 0
            ), "Invalid withdraw");
        // burn the liquidity in the locked setup
        withdrawReward(positionId);
        _setups[farmingPosition.setupIndex].totalSupply -= removedLiquidity;
        _removeLiquidity(positionId, setupIndex, removedLiquidity, false, amount0Min, amount1Min, burnData);
        if (positionId == 0) {
            _setupPositionsCount[setupIndex] -= removedLiquidity;
            if (_setupPositionsCount[setupIndex] == 0 && !_setups[setupIndex].active) {
                delete _setups[setupIndex];
            }
        }
    }

    function calculateFreeFarmingReward(uint256 positionId, bool isExt) public override view returns(uint256 reward) {
        FarmingPosition memory farmingPosition = _position[positionId];
        reward = ((_rewardPerTokenPerSetup[farmingPosition.setupIndex] - _rewardPerTokenPaid[positionId]) * farmingPosition.liquidityPoolTokenAmount) / 1e18;
        if (isExt) {
            uint256 currentEvent = block.timestamp < _setups[farmingPosition.setupIndex].endEvent ? block.timestamp : _setups[farmingPosition.setupIndex].endEvent;
            uint256 lastUpdateEvent = _setups[farmingPosition.setupIndex].lastUpdateEvent < _setups[farmingPosition.setupIndex].startEvent ? _setups[farmingPosition.setupIndex].startEvent : _setups[farmingPosition.setupIndex].lastUpdateEvent;
            uint256 rpt = (((currentEvent - lastUpdateEvent) * _setups[farmingPosition.setupIndex].rewardPerEvent) * 1e18) / _setups[farmingPosition.setupIndex].totalSupply;
            reward += (rpt * farmingPosition.liquidityPoolTokenAmount) / 1e18;
        }
        reward += farmingPosition.reward;
    }

    /** Private methods */

    function _setOrAddFarmingSetupInfo(FarmingSetupInfo memory info, bool add, bool disable, uint256 setupIndex) private {
        require(info.free, "free");
        FarmingSetupInfo memory farmingSetupInfo = info;
        farmingSetupInfo.eventDuration = farmingSetupInfo.eventDuration / TIME_SLOTS_IN_SECONDS;

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
                farmingSetupInfo.originalRewardPerEvent > 0 &&
                (farmingSetupInfo.free || farmingSetupInfo.maxStakeable > 0),
                "Invalid setup configuration"
            );

            (,,address[] memory tokenAddresses) = IAMM(farmingSetupInfo.ammPlugin).byLiquidityPool(farmingSetupInfo.liquidityPoolTokenAddress);
            farmingSetupInfo.ethereumAddress = address(0);
            if (farmingSetupInfo.involvingETH) {
                (farmingSetupInfo.ethereumAddress,,,,) = IAMM(farmingSetupInfo.ammPlugin).data();
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
            _setups[_farmingSetupsCount] = FarmingSetup(_farmingSetupsInfoCount, false, 0, 0, 0, 0, farmingSetupInfo.originalRewardPerEvent, 0);
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
            if(block.timestamp < setup.endEvent) {
                uint256 difference = info.originalRewardPerEvent < farmingSetupInfo.originalRewardPerEvent ? farmingSetupInfo.originalRewardPerEvent - info.originalRewardPerEvent : info.originalRewardPerEvent - farmingSetupInfo.originalRewardPerEvent;
                uint256 duration = setup.endEvent - block.timestamp;
                uint256 amount = difference * duration;
                if (amount > 0) {
                    if (info.originalRewardPerEvent > farmingSetupInfo.originalRewardPerEvent) {
                        require(_ensureTransfer(amount), "Insufficient reward in extension.");
                        _rewardReceived[setupIndex] += amount;
                    }
                    _updateFreeSetup(setupIndex, 0, 0, false);
                    setup.rewardPerEvent = info.originalRewardPerEvent;
                }
            }
            _setupsInfo[_setups[setupIndex].infoIndex].originalRewardPerEvent = info.originalRewardPerEvent;
        }
        if(_setupsInfo[_setups[setupIndex].infoIndex].renewTimes > 0) {
            _setupsInfo[_setups[setupIndex].infoIndex].renewTimes = info.renewTimes;
        }
    }

    function _transferToMeAndCheckAllowance(FarmingSetup memory setup, FarmingPositionRequest memory request) private returns(IAMM amm, uint256 liquidityPoolAmount, uint256 mainTokenAmount) {
        require(request.amount > 0, "No amount");
        require(!request.amountIsLiquidityPool, "LP");
        // retrieve the values
        amm = IAMM(_setupsInfo[setup.infoIndex].ammPlugin);
        liquidityPoolAmount = request.amountIsLiquidityPool ? request.amount : 0;
        mainTokenAmount = request.amountIsLiquidityPool ? 0 : request.amount;
        address[] memory tokens;
        uint256[] memory tokenAmounts;
        // if liquidity pool token amount is provided, the _position is opened by liquidity pool token amount
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

    function _toMinAmountsArray(uint256 amount0Min, uint256 amount1Min) private pure returns(uint256[] memory minAmounts) {
        minAmounts = new uint256[](2);
        minAmounts[0] = amount0Min;
        minAmounts[1] = amount1Min;
    }

    function _addLiquidity(uint256 setupIndex, FarmingPositionRequest memory request) private returns(LiquidityPoolParams memory liquidityPoolData, uint256 tokenAmount) {
        (IAMM amm, uint256 liquidityPoolAmount, uint256 mainTokenAmount) = _transferToMeAndCheckAllowance(_setups[setupIndex], request);
        // liquidity pool data struct for the AMM
        liquidityPoolData = LiquidityPoolParams(
            _setupsInfo[_setups[setupIndex].infoIndex].liquidityPoolTokenAddress,
            request.amountIsLiquidityPool ? liquidityPoolAmount : mainTokenAmount,
            _setupsInfo[_setups[setupIndex].infoIndex].mainTokenAddress,
            request.amountIsLiquidityPool,
            _setupsInfo[_setups[setupIndex].infoIndex].involvingETH,
            address(this),
            _toMinAmountsArray(request.amount0Min, request.amount1Min)
        );
        tokenAmount = mainTokenAmount;
        // amount is lp check
        if (liquidityPoolData.amountIsLiquidityPool || !_setupsInfo[_setups[setupIndex].infoIndex].involvingETH) {
            require(msg.value == 0, "ETH not involved");
        }
        if (liquidityPoolData.amountIsLiquidityPool) {
            return(liquidityPoolData, tokenAmount);
        }
        // retrieve the poolTokenAmount from the amm
        uint256[] memory addedLiquidityAmounts;
        (liquidityPoolData.amount, addedLiquidityAmounts,,) = amm.addLiquidity{value : liquidityPoolData.involvingETH ? msg.value : 0}(liquidityPoolData);
        require(addedLiquidityAmounts[0] >= request.amount0Min, "too little added");
        require(addedLiquidityAmounts[1] >= request.amount1Min, "too little added");
    }

    /** @dev helper function used to remove liquidity from a free _position or to burn item farm tokens and retrieve their content.
      * @param positionId id of the _position.
      * @param setupIndex index of the setup related to the item farm tokens.
      * @param isUnlock if we're removing liquidity from an unlock method or not.
     */
    function _removeLiquidity(uint256 positionId, uint256 setupIndex, uint256 removedLiquidity, bool isUnlock, uint256 amount0Min, uint256 amount1Min, bytes memory burnData) private {
        FarmingSetupInfo memory setupInfo = _setupsInfo[_setups[setupIndex].infoIndex];
        // retrieve the _position
        FarmingPosition storage farmingPosition = _position[positionId];
        // remaining liquidity
        uint256 remainingLiquidity;
        // we are removing liquidity using the setup items
        if (setupInfo.free && farmingPosition.creationEvent != 0 && positionId != 0) {
            // update the remaining liquidity
            remainingLiquidity = farmingPosition.liquidityPoolTokenAmount - removedLiquidity;
        }
        if (!setupInfo.free && _setups[setupIndex].active && !isUnlock) {
            _toggleSetup(setupIndex);
        } else if (setupInfo.free && positionId != 0) {
            if (_setups[farmingPosition.setupIndex].active && _setups[farmingPosition.setupIndex].endEvent <= block.timestamp) {
                _toggleSetup(farmingPosition.setupIndex);
            }
            // delete the farming _position after the withdraw
            if (remainingLiquidity == 0) {
                _setupPositionsCount[farmingPosition.setupIndex] -= 1;
                if (_setupPositionsCount[farmingPosition.setupIndex] == 0 && !_setups[farmingPosition.setupIndex].active) {
                    delete _setups[farmingPosition.setupIndex];
                }
                delete _position[positionId];
            } else {
                // update the creation event and amount
                require(setupInfo.minStakeable == 0, "Min stake: cannot remove partial liquidity");
                farmingPosition.liquidityPoolTokenAmount = remainingLiquidity;
            }
        }
        // create liquidity pool data struct for the AMM
        LiquidityPoolParams memory lpData = LiquidityPoolParams(
            setupInfo.liquidityPoolTokenAddress,
            removedLiquidity,
            setupInfo.mainTokenAddress,
            true,
            setupInfo.involvingETH,
            burnData.length > 0 ? msg.sender : address(this),
            _toMinAmountsArray(amount0Min, amount1Min)
        );
        _safeApprove(lpData.liquidityPoolAddress, setupInfo.ammPlugin, lpData.amount);
        (, uint256[] memory removedLiquidityAmounts, address[] memory tokens) = IAMM(setupInfo.ammPlugin).removeLiquidity(lpData);
        require(removedLiquidityAmounts[0] >= amount0Min, "too little received");
        require(removedLiquidityAmounts[1] >= amount1Min, "too little received");

        if(burnData.length > 0 ) {
            _burnFee(burnData);
        } else {
            if(lpData.involvingETH) {
                (address eth,,) = IAMM(setupInfo.ammPlugin).data();
                tokens[0] = tokens[0] == eth ? address(0) : tokens[0];
                tokens[1] = tokens[1] == eth ? address(0) : tokens[1];
            }
            uint256 feeAmount0 = _payFee(tokens[0], removedLiquidityAmounts[0]);
            uint256 feeAmount1 = _payFee(tokens[1], removedLiquidityAmounts[1]);
            _safeTransfer(tokens[0], msg.sender, removedLiquidityAmounts[0] - feeAmount0);
            _safeTransfer(tokens[1], msg.sender, removedLiquidityAmounts[1] - feeAmount1);
        }
    }

    function _payFee(address tokenAddress, uint256 feeAmount) private returns (uint256 feePaid) {
        IFarmFactory farmFactory = IFarmFactory(initializer);
        address factoryOfFactories = farmFactory.initializer();
        if(tokenAddress != address(0)) {
            _safeApprove(tokenAddress, factoryOfFactories, feeAmount);
        }
        feePaid = farmFactory.payFee{value : tokenAddress != address(0) ? 0 : feeAmount}(address(this), tokenAddress, feeAmount, "");
        if(tokenAddress != address(0)) {
            _safeApprove(tokenAddress, factoryOfFactories, 0);
        }
    }

    function _burnFee(bytes memory burnData) private returns (uint256) {
        (, burnData) = abi.decode(burnData, (bool, bytes));
        return IFarmFactory(initializer).burnOrTransferToken(msg.sender, burnData);
    }

    /** @dev updates the free setup with the given index.
      * @param setupIndex index of the setup that we're updating.
      * @param amount amount of liquidity that we're adding/removeing.
      * @param positionId _position id.
      * @param fromExit if it's from an exit or not.
     */
    function _updateFreeSetup(uint256 setupIndex, uint256 amount, uint256 positionId, bool fromExit) private {
        uint256 currentEvent = block.timestamp < _setups[setupIndex].endEvent ? block.timestamp : _setups[setupIndex].endEvent;
        if (_setups[setupIndex].totalSupply != 0) {
            uint256 lastUpdateEvent = _setups[setupIndex].lastUpdateEvent < _setups[setupIndex].startEvent ? _setups[setupIndex].startEvent : _setups[setupIndex].lastUpdateEvent;
            _rewardPerTokenPerSetup[setupIndex] += (((currentEvent - lastUpdateEvent) * _setups[setupIndex].rewardPerEvent) * 1e18) / _setups[setupIndex].totalSupply;
        }
        // update the last event update variable
        _setups[setupIndex].lastUpdateEvent = currentEvent;
        if (positionId != 0) {
            _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[setupIndex];
        }
        if (amount > 0) {
            fromExit ? _setups[setupIndex].totalSupply -= amount : _setups[setupIndex].totalSupply += amount;
        }
    }

    function _toggleSetup(uint256 setupIndex) private {
        FarmingSetup storage setup = _setups[setupIndex];
        // require(!setup.active || block.timestamp >= setup.endEvent, "Not valid activation");

        require(block.timestamp > _setupsInfo[setup.infoIndex].startEvent, "Too early for this setup");

        if (setup.active && block.timestamp >= setup.endEvent && _setupsInfo[setup.infoIndex].renewTimes == 0) {
            setup.active = false;
            return;
        } else if (block.timestamp >= setup.startEvent && block.timestamp < setup.endEvent && setup.active) {
            setup.active = false;
            _setupsInfo[setup.infoIndex].renewTimes = 0;
            uint256 amount = (setup.endEvent - block.timestamp) * setup.rewardPerEvent;
            setup.endEvent = block.timestamp;
            if (_setupsInfo[setup.infoIndex].free) {
                _updateFreeSetup(setupIndex, 0, 0, false);
            }
            _rewardReceived[setupIndex] -= amount;
            _giveBack(amount);
            return;
        }

        bool wasActive = setup.active;
        uint256 eventDurationInSeconds = _setupsInfo[setup.infoIndex].eventDuration * TIME_SLOTS_IN_SECONDS;
        setup.active = _ensureTransfer(setup.rewardPerEvent * eventDurationInSeconds);

        if (setup.active && wasActive) {
            _rewardReceived[_farmingSetupsCount] = setup.rewardPerEvent * eventDurationInSeconds;
            // set new setup
            _setups[_farmingSetupsCount] = abi.decode(abi.encode(setup), (FarmingSetup));
            // update old setup
            _setups[setupIndex].active = false;
            // update new setup
            _setupsInfo[setup.infoIndex].renewTimes -= 1;
            _setupsInfo[setup.infoIndex].setupsCount += 1;
            _setupsInfo[setup.infoIndex].lastSetupIndex = _farmingSetupsCount;
            _setups[_farmingSetupsCount].startEvent = block.timestamp;
            _setups[_farmingSetupsCount].endEvent = block.timestamp + eventDurationInSeconds;
            _setups[_farmingSetupsCount].objectId = 0;
            _setups[_farmingSetupsCount].totalSupply = 0;
            _farmingSetupsCount += 1;
        } else if (setup.active && !wasActive) {
            _rewardReceived[setupIndex] = setup.rewardPerEvent * eventDurationInSeconds;
            // update new setup
            _setups[setupIndex].startEvent = block.timestamp;
            _setups[setupIndex].endEvent = block.timestamp + eventDurationInSeconds;
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
        bytes32 value = bytes32(uint256(uint160(_addr)));
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
        if (rewardTokenAddress == address(0)) {
            IFarmingExtension(host).backToYou{value : amount}(amount);
        } else {
            _safeApprove(rewardTokenAddress, host, amount);
            IFarmingExtension(host).backToYou(amount);
        }
    }

    /** @dev ensures the transfer from the contract to the extension.
      * @param amount amount to transfer.
     */
    function _ensureTransfer(uint256 amount) private returns(bool) {
        uint256 initialBalance = rewardTokenAddress == address(0) ? address(this).balance : IERC20(rewardTokenAddress).balanceOf(address(this));
        uint256 expectedBalance = initialBalance + amount;
        try IFarmingExtension(host).transferTo(amount) {} catch {}
        uint256 actualBalance = rewardTokenAddress == address(0) ? address(this).balance : IERC20(rewardTokenAddress).balanceOf(address(this));
        if(actualBalance == expectedBalance) {
            return true;
        }
        _giveBack(actualBalance - initialBalance);
        return false;
    }
}

interface IFarmFactory {
    function initializer() external view returns (address);
    function payFee(address sender, address tokenAddress, uint256 value, bytes calldata permitSignature) external payable returns (uint256 feePaid);
    function burnOrTransferToken(address sender, bytes calldata permitSignature) external payable returns(uint256 amountTransferedOrBurnt);
}