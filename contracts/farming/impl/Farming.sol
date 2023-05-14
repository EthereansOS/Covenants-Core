//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/IFarmingExtension.sol";
import "@ethereansos/swissknife/contracts/generic/impl/LazyInitCapableElement.sol";
import "../../amm-aggregator/model/IAMMAggregator.sol";
import { IERC20Full as IERC20, TransferUtilities, BehaviorUtilities } from "@ethereansos/swissknife/contracts/lib/GeneralUtilities.sol";
import "../../util/IERC721.sol";
import "../../util/IERC1155.sol";
import "../../util/INONGovRules.sol";

contract Farming is IFarming, LazyInitCapableElement, IERC721Receiver, IERC1155Receiver {
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

   function _lazyInit(bytes memory lazyInitData) internal override returns(bytes memory extensionInitResult) {
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
            address[] memory amms = IAMMAggregator(_ammAggregatorAddress).amms();
            SetupModel[] memory setupModels = abi.decode(farmingSeupModelBytes, (SetupModel[]));
            for(uint256 i = 0; i < setupModels.length; i++) {
                _setOrAddFarmingSetupModel(setupModels[i], true, false, 0, amms);
            }
        }
    }

    function _supportsInterface(bytes4 selector) internal override view returns(bool) {
    }

    modifier positionOwnerOnly(uint256 positionId) {
        Position memory positionEntry = _position[positionId];
        require( positionEntry.creationEvent != 0 && positionEntry.owner == msg.sender, "Not owned");
        _;
    }

    receive() external payable {}

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

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
        address[] memory amms = IAMMAggregator(_ammAggregatorAddress).amms();
        for (uint256 i = 0; i < setupModelConfigurationArray.length; i++) {
            _setOrAddFarmingSetupModel(setupModelConfigurationArray[i].model, setupModelConfigurationArray[i].add, setupModelConfigurationArray[i].disable, setupModelConfigurationArray[i].index, amms);
        }
    }

    function setups() external override view returns (Setup[] memory setupArray) {
        setupArray = new Setup[](_setupsCount);
        for (uint256 i = 0; i < setupArray.length; i++) {
            setupArray[i] = _setup[i];
        }
    }

    function setup(uint256 setupIndex) external override view returns (Setup memory setupInstance, SetupModel memory setupModel) {
        if(setupIndex < _setupsCount) {
            return (_setup[setupIndex], _setupModel[_setup[setupIndex].modelIndex]);
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
        Setup memory chosenSetup = _setup[request.setupIndexOrPositionId];
        if(!chosenSetup.active) {
            activateSetup(chosenSetup.modelIndex);
        }

        address owner = request.owner != address(0) ? request.owner : msg.sender;
        positionId = uint256(BehaviorUtilities.randomKey(_indexKey++));
        (uint256 liquidityPoolAmount, uint256 liquidityPoolId) = _addLiquidity(request.setupIndexOrPositionId, request, true);
        _updateSetup(request.setupIndexOrPositionId, liquidityPoolAmount, positionId, false);
        _position[positionId] = Position({
            owner: owner,
            setupIndex : request.setupIndexOrPositionId,
            creationEvent: block.timestamp,
            liquidityPoolId: liquidityPoolId,
            liquidityPoolAmount: liquidityPoolAmount,
            reward: 0
        });
        _setupPositionsCount[request.setupIndexOrPositionId] += 1;
        emit PositionOpened(positionId, owner);
    }

    function addLiquidity(PositionRequest memory request) external override payable positionOwnerOnly(request.setupIndexOrPositionId) {
        uint256 positionId = request.setupIndexOrPositionId;
        Position storage farmingPosition = _position[positionId];
        uint256 setupIndex = farmingPosition.setupIndex;
        require(_setup[setupIndex].active, "Setup not active");
        require(_setup[setupIndex].startEvent <= block.timestamp && _setup[setupIndex].endEvent > block.timestamp, "Invalid setup");
        Setup storage chosenSetup = _setup[farmingPosition.setupIndex];

        (uint256 liquidityPoolAmount,) = _addLiquidity(farmingPosition.setupIndex, request, false);
        _rewardPerTokenPerSetup[farmingPosition.setupIndex] += (((block.timestamp - chosenSetup.lastUpdateEvent) * chosenSetup.rewardPerEvent) * 1e18) / chosenSetup.totalSupply;
        farmingPosition.reward = calculateReward(positionId, false);
        _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[farmingPosition.setupIndex];
        farmingPosition.liquidityPoolAmount += liquidityPoolAmount;
        chosenSetup.lastUpdateEvent = block.timestamp;
        chosenSetup.totalSupply += liquidityPoolAmount;
    }

    function withdrawReward(uint256 positionId) public positionOwnerOnly(positionId) {
        Position storage farmingPosition = _position[positionId];
        uint256 reward = farmingPosition.reward;
        uint256 currentEvent = block.timestamp;

        currentEvent = currentEvent > _setup[farmingPosition.setupIndex].endEvent ? _setup[farmingPosition.setupIndex].endEvent : currentEvent;
        _rewardPerTokenPerSetup[farmingPosition.setupIndex] += (((currentEvent - _setup[farmingPosition.setupIndex].lastUpdateEvent) * _setup[farmingPosition.setupIndex].rewardPerEvent) * 1e18) / _setup[farmingPosition.setupIndex].totalSupply;
        reward = calculateReward(positionId, false);
        _rewardPerTokenPaid[positionId] = _rewardPerTokenPerSetup[farmingPosition.setupIndex];
        farmingPosition.reward = 0;
        _setup[farmingPosition.setupIndex].lastUpdateEvent = currentEvent;

        if (reward > 0) {
            rewardTokenAddress.safeTransfer(farmingPosition.owner, reward);
            rewardPaidPerSetup[farmingPosition.setupIndex] += reward;
        }
        if (_setup[farmingPosition.setupIndex].endEvent <= block.timestamp) {
            if (_setup[farmingPosition.setupIndex].active) {
                _toggleSetup(farmingPosition.setupIndex);
            }
        }
    }

    function removeLiquidity(uint256 positionId, uint256 amount, uint256[] calldata amountsMin, bytes memory burnData) external override positionOwnerOnly(positionId) {
        Position memory farmingPosition = _position[positionId];
        require(amount > 0 && amount <= farmingPosition.liquidityPoolAmount, "Amount");
        withdrawReward(positionId);
        _setup[farmingPosition.setupIndex].totalSupply -= amount;
        _removeLiquidity(positionId, farmingPosition.setupIndex, amount, amountsMin, burnData);
    }

    function calculateReward(uint256 positionId, bool isExt) public override view returns(uint256 reward) {
        Position memory farmingPosition = _position[positionId];
        reward = ((_rewardPerTokenPerSetup[farmingPosition.setupIndex] - _rewardPerTokenPaid[positionId]) * farmingPosition.liquidityPoolAmount) / 1e18;
        if (isExt) {
            uint256 currentEvent = block.timestamp < _setup[farmingPosition.setupIndex].endEvent ? block.timestamp : _setup[farmingPosition.setupIndex].endEvent;
            uint256 lastUpdateEvent = _setup[farmingPosition.setupIndex].lastUpdateEvent < _setup[farmingPosition.setupIndex].startEvent ? _setup[farmingPosition.setupIndex].startEvent : _setup[farmingPosition.setupIndex].lastUpdateEvent;
            uint256 rpt = (((currentEvent - lastUpdateEvent) * _setup[farmingPosition.setupIndex].rewardPerEvent) * 1e18) / _setup[farmingPosition.setupIndex].totalSupply;
            reward += (rpt * farmingPosition.liquidityPoolAmount) / 1e18;
        }
        reward += farmingPosition.reward;
    }

    function _setOrAddFarmingSetupModel(SetupModel memory setupModelInput, bool add, bool disable, uint256 setupIndex, address[] memory amms) private {
        SetupModel memory setupModel = setupModelInput;
        setupModel.duration = setupModel.duration / TIME_SLOTS_IN_SECONDS;

        if(add || !disable) {
            setupModel.renewTimes += setupModel.renewTimes == uint256(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) ? 0 : 1;
        }

        if (add) {
            require(
                setupModel.amm != address(0) &&
                setupModel.originalRewardPerEvent > 0,
                "model"
            );

            bool ammFound;
            for(uint256 i = 0; i < amms.length; i++) {
                if(amms[i] == setupModel.amm) {
                    ammFound = true;
                    break;
                }
            }
            require(ammFound, "AMM");

            IAMM ammPlugin = IAMM(setupModel.amm);
            (,,setupModel.tokenAddresses) = ammPlugin.byLiquidityPool(setupModel.liquidityPoolId);
            (setupModel.ethereumAddress,,, setupModel.liquidityPoolTokenType, setupModel.liquidityPoolCollectionAddress) = ammPlugin.data();
            bool mainTokenFound = false;
            bool ethTokenFound = false;
            for(uint256 i = 0; i < setupModel.tokenAddresses.length; i++) {
                if(setupModel.tokenAddresses[i] == setupModel.ethereumAddress) {
                    ethTokenFound = true;
                }
                if(setupModel.tokenAddresses[i] == setupModel.mainTokenAddress) {
                    mainTokenFound = true;
                } else {
                    emit SetupToken(setupModel.mainTokenAddress, setupModel.tokenAddresses[i]);
                }
            }
            require(mainTokenFound, "No main token");
            require(!setupModel.involvingETH || ethTokenFound, "No ETH token");
            setupModel.setupsCount = 0;
            setupModel.lastSetupIndex = _setupsCount;
            _setupModel[_setupModelsCount] = setupModel;
            _setup[_setupsCount] = Setup(_setupModelsCount, false, 0, 0, 0, setupModel.originalRewardPerEvent, 0);
            _setupModelsCount++;
            _setupsCount++;
            return;
        }

        Setup storage setupInstance = _setup[setupIndex];
        setupModel = _setupModel[_setup[setupIndex].modelIndex];

        if(disable) {
            require(setupInstance.active, "Not possible");
            _toggleSetup(setupIndex);
            return;
        }

        setupModelInput.renewTimes -= 1;

        if (setupInstance.active) {
            setupInstance = _setup[setupIndex];
            if(block.timestamp < setupInstance.endEvent) {
                uint256 difference = setupModelInput.originalRewardPerEvent < setupModel.originalRewardPerEvent ? setupModel.originalRewardPerEvent - setupModelInput.originalRewardPerEvent : setupModelInput.originalRewardPerEvent - setupModel.originalRewardPerEvent;
                uint256 duration = setupInstance.endEvent - block.timestamp;
                uint256 amount = difference * duration;
                if (amount > 0) {
                    if (setupModelInput.originalRewardPerEvent > setupModel.originalRewardPerEvent) {
                        require(_ensureTransfer(amount), "Insufficient reward in extension.");
                        rewardReceivedPerSetup[setupIndex] += amount;
                    }
                    _updateSetup(setupIndex, 0, 0, false);
                    setupInstance.rewardPerEvent = setupModelInput.originalRewardPerEvent;
                }
            }
            _setupModel[_setup[setupIndex].modelIndex].originalRewardPerEvent = setupModelInput.originalRewardPerEvent;
        }
        if(_setupModel[_setup[setupIndex].modelIndex].renewTimes > 0) {
            _setupModel[_setup[setupIndex].modelIndex].renewTimes = setupModelInput.renewTimes;
        }
    }

    function _transferToMeAndApprove(uint256 setupIndex, PositionRequest memory request) private returns (SetupModel memory setupModel, uint256 ethValue) {
        setupModel = _setupModel[_setup[setupIndex].modelIndex];
        require(setupModel.involvingETH || msg.value == 0, "ETH");
        for(uint256 i = 0; i < setupModel.tokenAddresses.length; i++) {
            require(request.amounts[i] > 0, "amount");
            if(setupModel.tokenAddresses[i] == setupModel.mainTokenAddress) {
                require(request.amounts[i] >= setupModel.minStakeable, "amount");
            }
            if(setupModel.involvingETH && setupModel.ethereumAddress == setupModel.tokenAddresses[i]) {
                require((ethValue = msg.value) == request.amounts[i], "ETH");
            } else {
                _comsumePermitSignature(setupModel.tokenAddresses[i], request.amounts[i], i < request.permitSignatures.length ? request.permitSignatures[i] : bytes(""));
                request.amounts[i] = setupModel.tokenAddresses[i].safeTransferFrom(msg.sender, address(this), request.amounts[i]);
                setupModel.tokenAddresses[i].safeApprove(setupModel.amm, request.amounts[i]);
            }
        }
    }

    function _comsumePermitSignature(address tokenAddress, uint256 amount, bytes memory permitSignature) private {
        if(permitSignature.length == 0) {
            return;
        }
        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = abi.decode(permitSignature, (uint256, uint8, bytes32, bytes32));
        IERC20(tokenAddress).permit(msg.sender, address(this), amount, deadline, v, r, s);
    }

    function _addLiquidity(uint256 setupIndex, PositionRequest memory request, bool create) private returns(uint256 liquidityPoolAmount, uint256 liquidityPoolId) {
        (SetupModel memory setupModel, uint256 ethValue) = _transferToMeAndApprove(setupIndex, request);
        if(create && !setupModel.liquidityPoolIdIsUnique) {
            (liquidityPoolAmount,, liquidityPoolId,) = IAMM(setupModel.amm).addLiquidityEnsuringPool{value : ethValue}(LiquidityPoolCreationParams(
                setupModel.tokenAddresses,
                request.amounts,
                setupModel.involvingETH,
                setupModel.createLiquidityAdditionalData,
                request.amountsMin,
                address(this),
                block.timestamp + 1000
            ));
            return (liquidityPoolAmount, liquidityPoolId);
        }
        liquidityPoolId = create ? setupModel.liquidityPoolId : _position[request.setupIndexOrPositionId].liquidityPoolId;
        if(setupModel.liquidityPoolTokenType != 20) {
            _approveLiquidityPool(setupModel, liquidityPoolId, 1);
        }
        (liquidityPoolAmount,,,) = IAMM(setupModel.amm).addLiquidity{value : ethValue}(LiquidityPoolParams(
            liquidityPoolId,
            request.amounts[0],
            setupModel.tokenAddresses[0],
            false,
            setupModel.involvingETH,
            setupModel.addLiquidityAdditionalData,
            request.amountsMin,
            address(this),
            block.timestamp + 1000
        ));
        if(setupModel.liquidityPoolTokenType != 20) {
            _approveLiquidityPool(setupModel, liquidityPoolId, 0);
        }
    }

    function _approveLiquidityPool(SetupModel memory setupModel, uint256 liquidityPoolId, uint256 amount) private {
        if(setupModel.liquidityPoolTokenType == 20) {
            return address(uint160(liquidityPoolId)).safeApprove(setupModel.amm, amount);
        }
        IERC721(setupModel.liquidityPoolCollectionAddress).setApprovalForAll(setupModel.amm, amount != 0);
    }

    function _removeLiquidity(uint256 positionId, uint256 setupIndex, uint256 amount, uint256[] memory amountsMin, bytes memory burnData) private {
        SetupModel memory setupModel = _setupModel[_setup[setupIndex].modelIndex];
        Position storage farmingPosition = _position[positionId];
        uint256 remainingLiquidity = farmingPosition.liquidityPoolAmount - amount;
        if (_setup[farmingPosition.setupIndex].active && _setup[farmingPosition.setupIndex].endEvent <= block.timestamp) {
            _toggleSetup(farmingPosition.setupIndex);
        }
        if (remainingLiquidity == 0) {
            _setupPositionsCount[farmingPosition.setupIndex] -= 1;
            if (_setupPositionsCount[farmingPosition.setupIndex] == 0 && !_setup[farmingPosition.setupIndex].active) {
                delete _setup[farmingPosition.setupIndex];
            }
            delete _position[positionId];
        } else {
            require(setupModel.minStakeable == 0, "Min stake: cannot remove partial liquidity");
            farmingPosition.liquidityPoolAmount = remainingLiquidity;
        }
        _approveLiquidityPool(setupModel, farmingPosition.liquidityPoolId, amount);
        (, uint256[] memory removedLiquidityAmounts,) = IAMM(setupModel.amm).removeLiquidity(LiquidityPoolParams(
            farmingPosition.liquidityPoolId,
            amount,
            setupModel.mainTokenAddress,
            true,
            setupModel.involvingETH,
            setupModel.removeLiquidityAdditionalData,
            amountsMin,
            burnData.length > 0 ? msg.sender : address(this),
            block.timestamp + 1000
        ));
        _approveLiquidityPool(setupModel, farmingPosition.liquidityPoolId, 0);

        if(burnData.length > 0 ) {
            _burnFee(burnData);
        } else {
            address[] memory tokens = setupModel.tokenAddresses;
            if(setupModel.involvingETH) {
                tokens[0] = tokens[0] == setupModel.ethereumAddress ? address(0) : tokens[0];
                tokens[1] = tokens[1] == setupModel.ethereumAddress ? address(0) : tokens[1];
            }
            uint256 feeAmount0 = _payFee(tokens[0], removedLiquidityAmounts[0]);
            uint256 feeAmount1 = _payFee(tokens[1], removedLiquidityAmounts[1]);
            tokens[0].safeTransfer(msg.sender, removedLiquidityAmounts[0] - feeAmount0);
            tokens[1].safeTransfer(msg.sender, removedLiquidityAmounts[1] - feeAmount1);
        }
    }

    function _payFee(address tokenAddress, uint256 feeAmount) private returns (uint256 feePaid) {
        INONGovRules farmingRules = INONGovRules(initializer);
        address farmingRulesInitializerAddress = farmingRules.initializer();
        if(tokenAddress != address(0)) {
            tokenAddress.safeApprove(farmingRulesInitializerAddress, feeAmount);
        }
        uint256 before = tokenAddress.balanceOf(address(this));
        farmingRules.payFee{value : tokenAddress != address(0) ? 0 : feeAmount}(address(this), tokenAddress, feeAmount, "");
        if(tokenAddress != address(0)) {
            tokenAddress.safeApprove(farmingRulesInitializerAddress, 0);
        }
        return before - tokenAddress.balanceOf(address(this));
    }

    function _burnFee(bytes memory burnData) private returns (uint256) {
        (, burnData) = abi.decode(burnData, (bool, bytes));
        return INONGovRules(initializer).burnOrTransferToken(msg.sender, burnData);
    }

    function _updateSetup(uint256 setupIndex, uint256 amount, uint256 positionId, bool fromExit) private {
        uint256 currentEvent = block.timestamp < _setup[setupIndex].endEvent ? block.timestamp : _setup[setupIndex].endEvent;
        if (_setup[setupIndex].totalSupply != 0) {
            uint256 lastUpdateEvent = _setup[setupIndex].lastUpdateEvent < _setup[setupIndex].startEvent ? _setup[setupIndex].startEvent : _setup[setupIndex].lastUpdateEvent;
            _rewardPerTokenPerSetup[setupIndex] += (((currentEvent - lastUpdateEvent) * _setup[setupIndex].rewardPerEvent) * 1e18) / _setup[setupIndex].totalSupply;
        }
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

        require(block.timestamp > _setupModel[setupInstance.modelIndex].startEvent, "Too early for this setup");

        if (setupInstance.active && block.timestamp >= setupInstance.endEvent && _setupModel[setupInstance.modelIndex].renewTimes == 0) {
            setupInstance.active = false;
            return;
        } else if (block.timestamp >= setupInstance.startEvent && block.timestamp < setupInstance.endEvent && setupInstance.active) {
            setupInstance.active = false;
            _setupModel[setupInstance.modelIndex].renewTimes = 0;
            uint256 amount = (setupInstance.endEvent - block.timestamp) * setupInstance.rewardPerEvent;
            setupInstance.endEvent = block.timestamp;
            _updateSetup(setupIndex, 0, 0, false);
            rewardReceivedPerSetup[setupIndex] -= amount;
            _giveBack(amount);
            return;
        }

        bool wasActive = setupInstance.active;
        uint256 eventDurationInSeconds = _setupModel[setupInstance.modelIndex].duration * TIME_SLOTS_IN_SECONDS;
        setupInstance.active = _ensureTransfer(setupInstance.rewardPerEvent * eventDurationInSeconds);

        if (setupInstance.active && wasActive) {
            rewardReceivedPerSetup[_setupsCount] = setupInstance.rewardPerEvent * eventDurationInSeconds;
            _setup[_setupsCount] = abi.decode(abi.encode(setupInstance), (Setup));
            _setup[setupIndex].active = false;
            _setupModel[setupInstance.modelIndex].renewTimes -= 1;
            _setupModel[setupInstance.modelIndex].setupsCount += 1;
            _setupModel[setupInstance.modelIndex].lastSetupIndex = _setupsCount;
            _setup[_setupsCount].startEvent = block.timestamp;
            _setup[_setupsCount].endEvent = block.timestamp + eventDurationInSeconds;
            _setup[_setupsCount].totalSupply = 0;
            _setupsCount += 1;
        } else if (setupInstance.active && !wasActive) {
            rewardReceivedPerSetup[setupIndex] = setupInstance.rewardPerEvent * eventDurationInSeconds;
            _setup[setupIndex].startEvent = block.timestamp;
            _setup[setupIndex].endEvent = block.timestamp + eventDurationInSeconds;
            _setup[setupIndex].totalSupply = 0;
            _setupModel[_setup[setupIndex].modelIndex].renewTimes -= 1;
        } else {
            _setupModel[_setup[setupIndex].modelIndex].renewTimes = 0;
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