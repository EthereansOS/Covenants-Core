//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/IFarmingExtension.sol";
import "@ethereansos/swissknife/contracts/generic/impl/LazyInitCapableElement.sol";
import "../../amm-aggregator/model/IAMM.sol";
import { IERC20Full as IERC20, TransferUtilities, BehaviorUtilities } from "@ethereansos/swissknife/contracts/lib/GeneralUtilities.sol";

contract Farming is IFarming, LazyInitCapableElement {
    using TransferUtilities for address;

    uint256 private constant ONE_HUNDRED = 1e18;
    uint256 private constant TIME_SLOTS_IN_SECONDS = 15;

    uint256 private _indexKey;

    address private _ammAggregatorAddress;

    address public override rewardTokenAddress;

    uint256 private _setupModelsCount;
    mapping(uint256 => SetupModel) private _setupModel;

    uint256 private _setupsCount;
    mapping(uint256 => Setup) private _setup;

    mapping(uint256 => Position) private _position;
    mapping(uint256 => uint256) private _rewardPerTokenPerSetup;
    mapping(uint256 => uint256) private _rewardPerTokenPaid;

    mapping(uint256 => uint256) private _setupPositionsCount;

    mapping(uint256 => uint256) public override rewardReceivedPerSetup;
    mapping(uint256 => uint256) public override rewardPaidPerSetup;

    constructor(bytes memory lazyInitData) LazyInitCapableElement(lazyInitData) {}

   function lazyInit(bytes memory lazyInitData) external override returns(bytes memory extensionInitResult) {
        address _host = host;
        require(_host != address(0), "host");

        (_ammAggregatorAddress, lazyInitData) = abi.decode(lazyInitData, (address, bytes));

        bytes memory farmingSeupModelBytes;
        address _rewardTokenAddress;
        (lazyInitData, _rewardTokenAddress, farmingSeupModelBytes) = abi.decode(lazyInitData, (bytes, address, bytes));

        if(keccak256(lazyInitData) != keccak256("")) {
            extensionInitResult = ILazyInitCapableElement(_host).lazyInit(lazyInitData);
        }

        emit RewardToken(rewardTokenAddress = _rewardTokenAddress);
        if(farmingSeupModelBytes.length > 0) {
            SetupModel[] memory FarmingSetupModels = abi.decode(farmingSeupModelBytes, (SetupModel[]));
            for(uint256 i = 0; i < FarmingSetupModels.length; i++) {
                _setOrAddFarmingSetupModel(FarmingSetupModels[i], true, false, 0);
            }
        }
    }

    function _supportsInterface(bytes4 selector) internal override view returns(bool) {
    }

    modifier positionOwnerOnly(uint256 positionId) {
        require(_position[positionId].uniqueOwner == msg.sender && _position[positionId].creationEvent != 0, "Not owned");
        _;
    }

    receive() external payable {}

    function position(uint256 positionId) external view returns(Position memory) {
        return _position[positionId];
    }

    function models() external override view returns (SetupModel[] memory modelArray) {
        modelArray = new SetupModel[](_setupModelsCount);
        for (uint256 i = 0; i < modelArray.length; i++) {
            modelArray[i] = _setupModel[i];
        }
    }

    function setModels(SetupModelConfiguration[] memory setupModelConfigurationArray) external override authorizedOnly {
        for (uint256 i = 0; i < setupModelConfigurationArray.length; i++) {
            _setOrAddFarmingSetupModel(setupModelConfigurationArray[i].model, setupModelConfigurationArray[i].add, setupModelConfigurationArray[i].disable, setupModelConfigurationArray[i].index);
        }
    }

    function setups() external override view returns (Setup[] memory setupArray) {
        setupArray = new Setup[](_setupsCount);
        for (uint256 i = 0; i < setupArray.length; i++) {
            setupArray[i] = _setup[i];
        }
    }

    function setup(uint256 setupIndex) external override view returns (Setup memory, SetupModel memory) {
        if(setupIndex < _setupsCount) {
            return (_setup[setupIndex], _setupModel[_setup[setupIndex].infoIndex]);
        }
    }

    function finalFlush(address[] calldata tokens, uint256[] calldata amounts) external override {
        for(uint256 i = 0; i < _setupsCount; i++) {
            require(_setupPositionsCount[i] == 0 && !_setup[i].active && _setup[i].totalSupply == 0, "Not Empty");
        }
        (,,,, address receiver) = IFarmingExtension(host).data();
        require(tokens.length == amounts.length, "length");
        for(uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amount = amounts[i];
            require(receiver != address(0));
            token.safeTransfer(receiver, amount);
        }
    }

    function activateSetup(uint256 setupModelIndex) public {
        require(_setupModel[setupModelIndex].renewTimes > 0 && !_setup[_setupModel[setupModelIndex].lastSetupIndex].active, "Invalid activation");
        _toggleSetup(_setupModel[setupModelIndex].lastSetupIndex);
    }

    function toggleSetup(uint256 setupModelIndex) external {
        require(_setup[_setupModel[setupModelIndex].lastSetupIndex].active && block.timestamp > _setup[_setupModel[setupModelIndex].lastSetupIndex].endEvent, "Invalid toggle.");
        _toggleSetup(_setupModel[setupModelIndex].lastSetupIndex);
    }

    function openPosition(PositionRequest memory request) external override payable returns(uint256 positionId) {
        if(!_setup[request.setupIndexOrPositionId].active) {
            activateSetup(_setup[request.setupIndexOrPositionId].modelIndex);
        }

        // retrieve the setup
        Setup storage chosenSetup = _setup[request.setupIndexOrPositionId];
        // retrieve the unique owner
        address uniqueOwner = (request.positionOwner != address(0)) ? request.positionOwner : msg.sender;
        // create the _position id
        positionId = uint256(BehaviorUtilities.randomKey(_indexKey++));
        require(_position[positionId].creationEvent == 0, "Invalid open");
        // create the lp data for the amm
        (LiquidityPoolParams memory liquidityPoolData, uint256 mainTokenAmount) = _addLiquidity(request.setupIndexOrPositionId, request);
        // calculate the reward
        uint256 reward;
        _updateSetup(request.setupIndexOrPositionId, liquidityPoolData.amount, positionId, false);
        _position[positionId] = Position({
            uniqueOwner: uniqueOwner,
            setupIndex : request.setupIndexOrPositionId,
            liquidityPoolTokenAmount: liquidityPoolData.amount,
            mainTokenAmount: mainTokenAmount,
            reward: reward,
            creationEvent: block.timestamp
        });
        _setupPositionsCount[request.setupIndexOrPositionId] += 1;
        emit PositionOpened(positionId, uniqueOwner);
    }

    function addLiquidity(PositionRequest memory request) external override payable positionOwnerOnly(request.setupIndexOrPositionId) {
        uint256 positionId = request.setupIndexOrPositionId;
        Position storage farmingPosition = _position[positionId];
        uint256 setupIndex = farmingPosition.setupIndex;
        require(_setup[setupIndex].active, "Setup not active");
        require(_setup[setupIndex].startEvent <= block.timestamp && _setup[setupIndex].endEvent > block.timestamp, "Invalid setup");
        // retrieve farming _position
        Setup storage chosenSetup = _setup[farmingPosition.setupIndex];
        // check if farmoing _position is valid
        // create the lp data for the amm
        (LiquidityPoolParams memory liquidityPoolData,) = _addLiquidity(farmingPosition.setupIndex, request);
        // rebalance the reward per token
        _rewardPerTokenPerSetup[farmingPosition.setupIndex] += (((block.timestamp - chosenSetup.lastUpdateEvent) * chosenSetup.rewardPerEvent) * 1e18) / chosenSetup.totalSupply;
        farmingPosition.reward = calculateReward(positionId, false);
        _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[farmingPosition.setupIndex];
        farmingPosition.liquidityPoolTokenAmount += liquidityPoolData.amount;
        // update the last event update variablex
        chosenSetup.lastUpdateEvent = block.timestamp;
        chosenSetup.totalSupply += liquidityPoolData.amount;
    }


    /** @dev this function allows a user to withdraw the reward.
      * @param positionId farming _position id.
     */
    function withdrawReward(uint256 positionId) public positionOwnerOnly(positionId) {
        // retrieve farming _position
        Position storage farmingPosition = _position[positionId];
        uint256 reward = farmingPosition.reward;
        uint256 currentEvent = block.timestamp;

        // rebalance setup
        currentEvent = currentEvent > _setup[farmingPosition.setupIndex].endEvent ? _setup[farmingPosition.setupIndex].endEvent : currentEvent;
        _rewardPerTokenPerSetup[farmingPosition.setupIndex] += (((currentEvent - _setup[farmingPosition.setupIndex].lastUpdateEvent) * _setup[farmingPosition.setupIndex].rewardPerEvent) * 1e18) / _setup[farmingPosition.setupIndex].totalSupply;
        reward = calculateReward(positionId, false);
        _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[farmingPosition.setupIndex];
        farmingPosition.reward = 0;
        // update the last event update variable
        _setup[farmingPosition.setupIndex].lastUpdateEvent = currentEvent;

        if (reward > 0) {
            rewardTokenAddress.safeTransfer(farmingPosition.uniqueOwner, reward);
            rewardPaidPerSetup[farmingPosition.setupIndex] += reward;
        }
        if (_setup[farmingPosition.setupIndex].endEvent <= block.timestamp) {
            if (_setup[farmingPosition.setupIndex].active) {
                _toggleSetup(farmingPosition.setupIndex);
            }
        }
    }

    function withdrawLiquidity(uint256 positionId, uint256 removedLiquidity, uint256[] calldata minAmounts, bytes memory burnData) external override positionOwnerOnly(positionId) {
        Position memory farmingPosition = _position[positionId];
        require(removedLiquidity <= farmingPosition.liquidityPoolTokenAmount, "Invalid withdraw");
        withdrawReward(positionId);
        _setup[farmingPosition.setupIndex].totalSupply -= removedLiquidity;
        _removeLiquidity(positionId, farmingPosition.setupIndex, removedLiquidity, false, minAmounts[0], minAmounts[1], burnData);
    }

    function calculateReward(uint256 positionId, bool isExt) public override view returns(uint256 reward) {
        Position memory farmingPosition = _position[positionId];
        reward = ((_rewardPerTokenPerSetup[farmingPosition.setupIndex] - _rewardPerTokenPaid[positionId]) * farmingPosition.liquidityPoolTokenAmount) / 1e18;
        if (isExt) {
            uint256 currentEvent = block.timestamp < _setup[farmingPosition.setupIndex].endEvent ? block.timestamp : _setup[farmingPosition.setupIndex].endEvent;
            uint256 lastUpdateEvent = _setup[farmingPosition.setupIndex].lastUpdateEvent < _setup[farmingPosition.setupIndex].startEvent ? _setup[farmingPosition.setupIndex].startEvent : _setup[farmingPosition.setupIndex].lastUpdateEvent;
            uint256 rpt = (((currentEvent - lastUpdateEvent) * _setup[farmingPosition.setupIndex].rewardPerEvent) * 1e18) / _setup[farmingPosition.setupIndex].totalSupply;
            reward += (rpt * farmingPosition.liquidityPoolTokenAmount) / 1e18;
        }
        reward += farmingPosition.reward;
    }

    /** Private methods */

    function _setOrAddFarmingSetupModel(SetupModel memory model, bool add, bool disable, uint256 setupIndex) private {
        SetupModel memory farmingSetupModel = model;
        farmingSetupModel.eventDuration = farmingSetupModel.eventDuration / TIME_SLOTS_IN_SECONDS;

        if(add || !disable) {
            farmingSetupModel.renewTimes = farmingSetupModel.renewTimes + 1;
            if(farmingSetupModel.renewTimes == 0) {
                farmingSetupModel.renewTimes = farmingSetupModel.renewTimes - 1;
            }
        }

        if (add) {
            require(
                farmingSetupModel.ammPlugin != address(0) &&
                farmingSetupModel.originalRewardPerEvent > 0 &&
                "Invalid setup configuration"
            );

            (,,address[] memory tokenAddresses) = IAMM(farmingSetupModel.ammPlugin).byLiquidityPool(farmingSetupModel.liquidityPoolId);
            farmingSetupModel.ethereumAddress = address(0);
            if (farmingSetupModel.involvingETH) {
                (farmingSetupModel.ethereumAddress,,,,) = IAMM(farmingSetupModel.ammPlugin).data();
            }
            bool mainTokenFound = false;
            bool ethTokenFound = false;
            for(uint256 z = 0; z < tokenAddresses.length; z++) {
                if(tokenAddresses[z] == farmingSetupModel.mainTokenAddress) {
                    mainTokenFound = true;
                    if(tokenAddresses[z] == farmingSetupModel.ethereumAddress) {
                        ethTokenFound = true;
                    }
                } else {
                    emit SetupToken(farmingSetupModel.mainTokenAddress, tokenAddresses[z]);
                    if(tokenAddresses[z] == farmingSetupModel.ethereumAddress) {
                        ethTokenFound = true;
                    }
                }
            }
            require(mainTokenFound, "No main token");
            require(!farmingSetupModel.involvingETH || ethTokenFound, "No ETH token");
            farmingSetupModel.setupsCount = 0;
            _setupModel[_setupModelsCount] = SetupModel;
            _setup[_setupsCount] = Setup(_setupModelsCount, false, 0, 0, 0, farmingSetupModel.originalRewardPerEvent, 0);
            _setupModel[_setupModelsCount].lastSetupIndex = _setupsCount;
            _setupModelsCount += 1;
            _setupsCount += 1;
            return;
        }

        Setup storage setupInstance = _setup[setupIndex];
        SetupModel = _setupModel[_setup[setupIndex].infoIndex];

        if(disable) {
            require(setupInstance.active, "Not possible");
            _toggleSetup(setupIndex);
            return;
        }

        model.renewTimes -= 1;

        if (setupInstance.active) {
            _setup = _setup[setupIndex];
            if(block.timestamp < setupInstance.endEvent) {
                uint256 difference = model.originalRewardPerEvent < farmingSetupModel.originalRewardPerEvent ? farmingSetupModel.originalRewardPerEvent - model.originalRewardPerEvent : model.originalRewardPerEvent - farmingSetupModel.originalRewardPerEvent;
                uint256 duration = setupInstance.endEvent - block.timestamp;
                uint256 amount = difference * duration;
                if (amount > 0) {
                    if (model.originalRewardPerEvent > farmingSetupModel.originalRewardPerEvent) {
                        require(_ensureTransfer(amount), "Insufficient reward in extension.");
                        rewardReceivedPerSetup[setupIndex] += amount;
                    }
                    _updateSetup(setupIndex, 0, 0, false);
                    setupInstance.rewardPerEvent = model.originalRewardPerEvent;
                }
            }
            _setupModel[_setup[setupIndex].infoIndex].originalRewardPerEvent = model.originalRewardPerEvent;
        }
        if(_setupModel[_setup[setupIndex].infoIndex].renewTimes > 0) {
            _setupModel[_setup[setupIndex].infoIndex].renewTimes = model.renewTimes;
        }
    }

    function _transferToMeAndCheckAllowance(Setup memory setupInstance, PositionRequest memory request) private returns(IAMM amm, uint256 liquidityPoolAmount, uint256 mainTokenAmount) {
      /*  uint256[] memory tokenAmounts = request.amounts;
        for(uint256 i = 0; i < tokenAmounts.length; i++) {
            require(tokenAmounts[i] > 0, "amount");
        }
        amm = IAMM(_setupModel[setupInstance.infoIndex].ammPlugin);
        liquidityPoolAmount = request.amountIsLiquidityPool ? request.amount : 0;
        mainTokenAmount = request.amountIsLiquidityPool ? 0 : request.amount;
        address[] memory tokens;
        // if liquidity pool token amount is provided, the _position is opened by liquidity pool token amount
        if(request.amountIsLiquidityPool) {
            _safeTransferFrom(_setupModel[setupInstance.infoIndex].liquidityPoolTokenAddress, msg.sender, address(this), liquidityPoolAmount);
            (tokenAmounts, tokens) = amm.byLiquidityPoolAmount(_setupModel[setupInstance.infoIndex].liquidityPoolTokenAddress, liquidityPoolAmount);
        } else {
            // else it is opened by the tokens amounts
            (liquidityPoolAmount, tokenAmounts, tokens) = amm.byTokenAmount(_setupModel[setupInstance.infoIndex].liquidityPoolTokenAddress, _setupModel[setupInstance.infoIndex].mainTokenAddress, mainTokenAmount);
        }

        // iterate the tokens and perform the transferFrom and the approve
        for(uint256 i = 0; i < tokens.length; i++) {
            if(tokens[i] == _setupModel[setupInstance.infoIndex].mainTokenAddress) {
                mainTokenAmount = tokenAmounts[i];
                require(mainTokenAmount >= _setupModel[setupInstance.infoIndex].minStakeable, "Invalid liquidity.");
                if(request.amountIsLiquidityPool) {
                    break;
                }
            }
            if(request.amountIsLiquidityPool) {
                continue;
            }
            if(_setupModel[setupInstance.infoIndex].involvingETH && _setupModel[setupInstance.infoIndex].ethereumAddress == tokens[i]) {
                require(msg.value == tokenAmounts[i], "Incorrect eth value");
            } else {
                _safeTransferFrom(tokens[i], msg.sender, address(this), tokenAmounts[i]);
                _safeApprove(tokens[i], _setupModel[setupInstance.infoIndex].ammPlugin, tokenAmounts[i]);
            }
        }*/
    }

    function _toMinAmountsArray(uint256 amount0Min, uint256 amount1Min) private pure returns(uint256[] memory minAmounts) {
        minAmounts = new uint256[](2);
        minAmounts[0] = amount0Min;
        minAmounts[1] = amount1Min;
    }

    function _addLiquidity(uint256 setupIndex, PositionRequest memory request) private returns(LiquidityPoolParams memory liquidityPoolData, uint256 tokenAmount) {
        (IAMM amm, uint256 liquidityPoolAmount, uint256 mainTokenAmount) = _transferToMeAndCheckAllowance(_setup[setupIndex], request);
        // liquidity pool data struct for the AMM
        liquidityPoolData = LiquidityPoolParams(
            _setupModel[_setup[setupIndex].infoIndex].liquidityPoolId,
            mainTokenAmount,
            _setupModel[_setup[setupIndex].infoIndex].mainTokenAddress,
            false,
            _setupModel[_setup[setupIndex].infoIndex].involvingETH,
            address(this),
            request.minAmounts
        );
        tokenAmount = mainTokenAmount;
        // amount is lp check
        if (liquidityPoolData.amountIsLiquidityPool || !_setupModel[_setup[setupIndex].infoIndex].involvingETH) {
            require(msg.value == 0, "ETH not involved");
        }
        if (liquidityPoolData.amountIsLiquidityPool) {
            return(liquidityPoolData, tokenAmount);
        }
        // retrieve the poolTokenAmount from the amm
        uint256[] memory addedLiquidityAmounts;
        (liquidityPoolData.amount, addedLiquidityAmounts,,) = amm.addLiquidity{value : liquidityPoolData.involvingETH ? msg.value : 0}(liquidityPoolData);
    }

    function _removeLiquidity(uint256 positionId, uint256 setupIndex, uint256 removedLiquidity, bool isUnlock, uint256 amount0Min, uint256 amount1Min, bytes memory burnData) private {
        SetupModel memory setupModel = _setupModel[_setup[setupIndex].modelIndex];
        // retrieve the _position
        Position storage farmingPosition = _position[positionId];
        // remaining liquidity
        uint256 remainingLiquidity;
        // we are removing liquidity using the setup items
        if (farmingPosition.creationEvent != 0 && positionId != 0) {
            // update the remaining liquidity
            remainingLiquidity = farmingPosition.liquidityPoolTokenAmount - removedLiquidity;
        }
        if (_setup[farmingPosition.setupIndex].active && _setup[farmingPosition.setupIndex].endEvent <= block.timestamp) {
            _toggleSetup(farmingPosition.setupIndex);
        }
        // delete the farming _position after the withdraw
        if (remainingLiquidity == 0) {
            _setupPositionsCount[farmingPosition.setupIndex] -= 1;
            if (_setupPositionsCount[farmingPosition.setupIndex] == 0 && !_setup[farmingPosition.setupIndex].active) {
                delete _setup[farmingPosition.setupIndex];
            }
            delete _position[positionId];
        } else {
            // update the creation event and amount
            require(setupModel.minStakeable == 0, "Min stake: cannot remove partial liquidity");
            farmingPosition.liquidityPoolTokenAmount = remainingLiquidity;
        }
        // create liquidity pool data struct for the AMM
        LiquidityPoolParams memory lpData = LiquidityPoolParams(
            setupModel.liquidityPoolId,
            removedLiquidity,
            setupModel.mainTokenAddress,
            true,
            setupModel.involvingETH,
            burnData.length > 0 ? msg.sender : address(this),
            _toMinAmountsArray(amount0Min, amount1Min)
        );
        lpData.liquidityPoolAddress.safeApprove(setupModel.ammPlugin, lpData.amount);
        (, uint256[] memory removedLiquidityAmounts, address[] memory tokens) = IAMM(setupModel.ammPlugin).removeLiquidity(lpData);
        require(removedLiquidityAmounts[0] >= amount0Min, "too little received");
        require(removedLiquidityAmounts[1] >= amount1Min, "too little received");

        if(burnData.length > 0 ) {
            _burnFee(burnData);
        } else {
            if(lpData.involvingETH) {
                (address eth,,) = IAMM(setupModel.ammPlugin).data();
                tokens[0] = tokens[0] == eth ? address(0) : tokens[0];
                tokens[1] = tokens[1] == eth ? address(0) : tokens[1];
            }
            uint256 feeAmount0 = _payFee(tokens[0], removedLiquidityAmounts[0]);
            uint256 feeAmount1 = _payFee(tokens[1], removedLiquidityAmounts[1]);
            tokens[0].safeTransfer(msg.sender, removedLiquidityAmounts[0] - feeAmount0);
            tokens[1].safeTransfer(msg.sender, removedLiquidityAmounts[1] - feeAmount1);
        }
    }

    function _payFee(address tokenAddress, uint256 feeAmount) private returns (uint256 feePaid) {
        IFarmFactory farmFactory = IFarmFactory(initializer);
        address factoryOfFactories = farmFactory.initializer();
        if(tokenAddress != address(0)) {
            tokenAddress.safeApprove(factoryOfFactories, feeAmount);
        }
        feePaid = farmFactory.payFee{value : tokenAddress != address(0) ? 0 : feeAmount}(address(this), tokenAddress, feeAmount, "");
        if(tokenAddress != address(0)) {
            tokenAddress.safeApprove(factoryOfFactories, 0);
        }
    }

    function _burnFee(bytes memory burnData) private returns (uint256) {
        (, burnData) = abi.decode(burnData, (bool, bytes));
        return IFarmFactory(initializer).burnOrTransferToken(msg.sender, burnData);
    }

    function _updateSetup(uint256 setupIndex, uint256 amount, uint256 positionId, bool fromExit) private {
        uint256 currentEvent = block.timestamp < _setup[setupIndex].endEvent ? block.timestamp : _setup[setupIndex].endEvent;
        if (_setup[setupIndex].totalSupply != 0) {
            uint256 lastUpdateEvent = _setup[setupIndex].lastUpdateEvent < _setup[setupIndex].startEvent ? _setup[setupIndex].startEvent : _setup[setupIndex].lastUpdateEvent;
            _rewardPerTokenPerSetup[setupIndex] += (((currentEvent - lastUpdateEvent) * _setup[setupIndex].rewardPerEvent) * 1e18) / _setup[setupIndex].totalSupply;
        }
        // update the last event update variable
        _setup[setupIndex].lastUpdateEvent = currentEvent;
        if (positionId != 0) {
            _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[setupIndex];
        }
        if (amount > 0) {
            fromExit ? _setup[setupIndex].totalSupply -= amount : _setup[setupIndex].totalSupply += amount;
        }
    }

    function _toggleSetup(uint256 setupIndex) private {
        Setup storage setupInstance = _setup[setupIndex];

        require(block.timestamp > _setupModel[setupInstance.infoIndex].startEvent, "Too early for this setup");

        if (setupInstance.active && block.timestamp >= setupInstance.endEvent && _setupModel[setupInstance.infoIndex].renewTimes == 0) {
            setupInstance.active = false;
            return;
        } else if (block.timestamp >= setupInstance.startEvent && block.timestamp < setupInstance.endEvent && setupInstance.active) {
            setupInstance.active = false;
            _setupModel[setupInstance.infoIndex].renewTimes = 0;
            uint256 amount = (setupInstance.endEvent - block.timestamp) * setupInstance.rewardPerEvent;
            setupInstance.endEvent = block.timestamp;
            _updateSetup(setupIndex, 0, 0, false);
            rewardReceivedPerSetup[setupIndex] -= amount;
            _giveBack(amount);
            return;
        }

        bool wasActive = setupInstance.active;
        uint256 eventDurationInSeconds = _setupModel[setupInstance.infoIndex].eventDuration * TIME_SLOTS_IN_SECONDS;
        setupInstance.active = _ensureTransfer(setupInstance.rewardPerEvent * eventDurationInSeconds);

        if (setupInstance.active && wasActive) {
            rewardReceivedPerSetup[_setupsCount] = setupInstance.rewardPerEvent * eventDurationInSeconds;
            // set new setup
            _setup[_setupsCount] = abi.decode(abi.encode(_setup), (Setup));
            // update old setup
            _setup[setupIndex].active = false;
            // update new setup
            _setupModel[setupInstance.infoIndex].renewTimes -= 1;
            _setupModel[setupInstance.infoIndex].setupsCount += 1;
            _setupModel[setupInstance.infoIndex].lastSetupIndex = _setupsCount;
            _setup[_setupsCount].startEvent = block.timestamp;
            _setup[_setupsCount].endEvent = block.timestamp + eventDurationInSeconds;
            _setup[_setupsCount].totalSupply = 0;
            _setupsCount += 1;
        } else if (setupInstance.active && !wasActive) {
            rewardReceivedPerSetup[setupIndex] = setupInstance.rewardPerEvent * eventDurationInSeconds;
            // update new setup
            _setup[setupIndex].startEvent = block.timestamp;
            _setup[setupIndex].endEvent = block.timestamp + eventDurationInSeconds;
            _setup[setupIndex].totalSupply = 0;
            _setupModel[_setup[setupIndex].infoIndex].renewTimes -= 1;
        } else {
            _setupModel[_setup[setupIndex].infoIndex].renewTimes = 0;
        }
    }

    function _giveBack(uint256 amount) private {
        if(amount == 0) {
            return;
        }
        rewardTokenAddress.safeApprove(host, amount);
        IFarmingExtension(host).backToYou{value : rewardTokenAddress == address(0) ? amount : 0}(amount);
    }

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