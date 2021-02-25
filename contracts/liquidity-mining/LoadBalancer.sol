//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../amm-aggregator/common/IAMM.sol";
import "./util/IERC20.sol";
import "./ILoadBalancer.sol";
import "./IFarmMain.sol";
import "./IFarmFactory.sol";

contract LoadBalancer is ILoadBalancer {

    // farm main address
    address private _farmMainAddress;
    // factory address that will create clones of this contract
    address public _factory;
    // positions
    mapping(uint256 => FarmingPosition) public _positions;
    // available reward
    uint256 private _availableReward;
    // reward token address
    address private _rewardTokenAddress;
    // reward per token
    uint256 private _rewardPerToken;
    // mapping containing the reward per token paid per position
    mapping(uint256 => uint256) private _rewardPerTokenPaid;
    // load balancer pinned free farming setup info
    FarmingSetupInfo private _pinnedSetupInfo;
    FarmingSetup private _pinnedSetup;
    // new or transferred farming position event
    event Transfer(uint256 indexed positionId, address indexed from, address indexed to);

    /** @dev byPositionOwner modifier used to check for unauthorized accesses. */
    modifier byPositionOwner(uint256 positionId) {
        require(_positions[positionId].uniqueOwner == msg.sender && _positions[positionId].creationBlock != 0, "Not owned");
        _;
    }

    function init(address farmMainAddress, uint256 minStakeable, address ammPlugin, address lptAddress, address ethereumAddress, bool involvingETH) public {
        require(_factory == address(0), "Unauthorized");
        require((_farmMainAddress = farmMainAddress) != address(0), "Invalid FarmMain address");
        _factory = msg.sender;
        require((_rewardTokenAddress = IFarmMain(_farmMainAddress)._rewardTokenAddress()) != address(0), "Invalid reward token address");
        _pinnedSetupInfo = FarmingSetupInfo(true, 0, 0, minStakeable, 0, 0, ammPlugin, lptAddress, address(0), ethereumAddress, involvingETH, 0, 0, 0);
        _pinnedSetup = FarmingSetup(0, true, 0, 0, 0, 0, 0, 0);
    }

    function active() public view returns(bool) {
        require(_farmMainAddress != address(0), "No FarmMain set");
        return IFarmMain(_farmMainAddress).loadBalancerActive();
    }

    function rebalancePinnedSetup(uint256 amount, bool add, uint256 endBlock) public override {
        require(msg.sender == _farmMainAddress, "Unautorized.");
        if (amount > 0) {
            add ? _availableReward += amount : _availableReward -= amount;
        }
        // TODO: calculate stuff
        if (_pinnedSetup.endBlock < endBlock) {
            _pinnedSetup.endBlock = endBlock;
        }
    }

    function openPosition(FarmingPositionRequest memory request) public payable returns(uint256 positionId) {
        require(active() && block.number < _pinnedSetup.endBlock, "Not active.");
        // retrieve the unique owner
        address uniqueOwner = (request.positionOwner != address(0)) ? request.positionOwner : msg.sender;
        // create the position id
        positionId = uint256(keccak256(abi.encode(uniqueOwner)));
        // create the lp data for the amm
        (LiquidityPoolData memory liquidityPoolData, uint256 mainTokenAmount) = _addLiquidity(request);
        // calculate the reward
        uint256 reward;
        uint256 lockedRewardPerBlock;
        if (_pinnedSetup.totalSupply != 0) {
            uint256 lastUpdateBlock = _pinnedSetup.lastUpdateBlock < _pinnedSetup.startBlock ? _pinnedSetup.startBlock : _pinnedSetup.lastUpdateBlock;
            _rewardPerToken += (((block.number - lastUpdateBlock) * _pinnedSetup.rewardPerBlock) * 1e18) / _pinnedSetup.totalSupply;
        }
        _rewardPerTokenPaid[positionId] = _rewardPerToken;
        _pinnedSetup.totalSupply += liquidityPoolData.amount;
        _pinnedSetup.lastUpdateBlock = block.number;
        _positions[positionId] = FarmingPosition({
            uniqueOwner: uniqueOwner,
            setupIndex : 0,
            liquidityPoolTokenAmount: liquidityPoolData.amount,
            mainTokenAmount: mainTokenAmount,
            reward: reward,
            lockedRewardPerBlock: lockedRewardPerBlock,
            creationBlock: block.number
        });
        emit Transfer(positionId, address(0), uniqueOwner);
    }

    function addLiquidity(uint256 positionId, FarmingPositionRequest memory request) public payable byPositionOwner(positionId) {
        require(active() && block.number < _pinnedSetup.endBlock, "Not active.");
        // retrieve farming position
        FarmingPosition storage farmingPosition = _positions[positionId];
        // create the lp data for the amm
        (LiquidityPoolData memory liquidityPoolData,) = _addLiquidity(request);
        // rebalance the reward per token
        _rewardPerToken += (((block.number - _pinnedSetup.lastUpdateBlock) * _pinnedSetup.rewardPerBlock) * 1e18) / _pinnedSetup.totalSupply;
        farmingPosition.reward = calculateFreeFarmingReward(positionId, false);
        _rewardPerTokenPaid[positionId] = _rewardPerToken;
        // update the last block update variable
        _pinnedSetup.lastUpdateBlock = block.number;
        _pinnedSetup.totalSupply += liquidityPoolData.amount;
    }

    function _addLiquidity(FarmingPositionRequest memory request) private returns(LiquidityPoolData memory liquidityPoolData, uint256 tokenAmount) {
        (IAMM amm, uint256 liquidityPoolAmount, uint256 mainTokenAmount) = _transferToMeAndCheckAllowance(request);
        // liquidity pool data struct for the AMM
        liquidityPoolData = LiquidityPoolData(
            _pinnedSetupInfo.liquidityPoolTokenAddress,
            request.amountIsLiquidityPool ? liquidityPoolAmount : mainTokenAmount,
            _pinnedSetupInfo.mainTokenAddress,
            request.amountIsLiquidityPool,
            _pinnedSetupInfo.involvingETH,
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

    /** @dev this function allows a user to withdraw the reward.
      * @param positionId farming position id.
     */
    function withdrawReward(uint256 positionId) public byPositionOwner(positionId) {
        // retrieve farming position
        FarmingPosition storage farmingPosition = _positions[positionId];
        uint256 reward = farmingPosition.reward;
        uint256 updateBlock = block.number < _pinnedSetup.endBlock ? block.number : _pinnedSetup.endBlock;
        // rebalance setup
        _rewardPerToken += (((updateBlock - _pinnedSetup.lastUpdateBlock) * _pinnedSetup.rewardPerBlock) * 1e18) / _pinnedSetup.totalSupply;
        // update the last block update variable
        _pinnedSetup.lastUpdateBlock = updateBlock;
        reward = calculateFreeFarmingReward(positionId, false);
        _rewardPerTokenPaid[positionId] = _rewardPerToken;
        farmingPosition.reward = 0;
        require(reward > 0, "No reward?");
        // transfer the reward
        _rewardTokenAddress != address(0) ? _safeTransfer(_rewardTokenAddress, farmingPosition.uniqueOwner, reward) : payable(farmingPosition.uniqueOwner).transfer(reward);
    }

    function withdrawLiquidity(uint256 positionId, bool unwrapPair, uint256 removedLiquidity) byPositionOwner(positionId) public {
        withdrawReward(positionId);
        _pinnedSetup.totalSupply -= removedLiquidity;
        _removeLiquidity(positionId, unwrapPair, removedLiquidity);
    }

    function calculateFreeFarmingReward(uint256 positionId, bool isExt) public view returns(uint256 reward) {
        FarmingPosition memory farmingPosition = _positions[positionId];
        reward = ((_rewardPerToken - _rewardPerTokenPaid[positionId]) * farmingPosition.liquidityPoolTokenAmount) / 1e18;
        if (isExt) {
            uint256 rpt = (((block.number - _pinnedSetup.startBlock) * _pinnedSetup.rewardPerBlock) * 1e18) / _pinnedSetup.totalSupply;
            reward += ((rpt - _rewardPerTokenPaid[positionId]) * farmingPosition.liquidityPoolTokenAmount) / 1e18;
        }
        reward += farmingPosition.reward;
    }

    function _transferToMeAndCheckAllowance(FarmingPositionRequest memory request) private returns(IAMM amm, uint256 liquidityPoolAmount, uint256 mainTokenAmount) {
        require(request.amount > 0, "No amount");
        // retrieve the values
        amm = IAMM(_pinnedSetupInfo.ammPlugin);
        require(request.amount >= _pinnedSetupInfo.minStakeable, "Invalid liquidity.");
        liquidityPoolAmount = request.amountIsLiquidityPool ? request.amount : 0;
        mainTokenAmount = request.amountIsLiquidityPool ? 0 : request.amount;
        address[] memory tokens;
        uint256[] memory tokenAmounts;
        // if liquidity pool token amount is provided, the position is opened by liquidity pool token amount
        if(request.amountIsLiquidityPool) {
            _safeTransferFrom(_pinnedSetupInfo.liquidityPoolTokenAddress, msg.sender, address(this), liquidityPoolAmount);
            (tokenAmounts, tokens) = amm.byLiquidityPoolAmount(_pinnedSetupInfo.liquidityPoolTokenAddress, liquidityPoolAmount);
        } else {
            // else it is opened by the tokens amounts
            (liquidityPoolAmount, tokenAmounts, tokens) = amm.byTokenAmount(_pinnedSetupInfo.liquidityPoolTokenAddress, _pinnedSetupInfo.mainTokenAddress, mainTokenAmount);
        }

        // iterate the tokens and perform the transferFrom and the approve
        for(uint256 i = 0; i < tokens.length; i++) {
            if(tokens[i] == _pinnedSetupInfo.mainTokenAddress) {
                mainTokenAmount = tokenAmounts[i];
                if(request.amountIsLiquidityPool) {
                    break;
                }
            }
            if(request.amountIsLiquidityPool) {
                continue;
            }
            if(_pinnedSetupInfo.involvingETH && _pinnedSetupInfo.ethereumAddress == tokens[i]) {
                require(msg.value == tokenAmounts[i], "Incorrect eth value");
            } else {
                _safeTransferFrom(tokens[i], msg.sender, address(this), tokenAmounts[i]);
                _safeApprove(tokens[i], _pinnedSetupInfo.ammPlugin, tokenAmounts[i]);
            }
        }
    }

    /** @dev helper function used to remove liquidity from a free position or to burn item farm tokens and retrieve their content.
      * @param positionId id of the position.
      * @param unwrapPair whether to unwrap the liquidity pool tokens or not.
      * @param removedLiquidity amount of liquidity to remove.
     */
    function _removeLiquidity(uint256 positionId, bool unwrapPair, uint256 removedLiquidity) private {
        // create liquidity pool data struct for the AMM
        LiquidityPoolData memory lpData = LiquidityPoolData(
            _pinnedSetupInfo.liquidityPoolTokenAddress,
            removedLiquidity,
            _pinnedSetupInfo.mainTokenAddress,
            true,
            _pinnedSetupInfo.involvingETH,
            msg.sender
        );
        // retrieve the position
        FarmingPosition storage farmingPosition = _positions[positionId];
        // remaining liquidity
        uint256 remainingLiquidity = farmingPosition.liquidityPoolTokenAmount - removedLiquidity;
        // retrieve fee stuff
        (uint256 exitFeePercentage, address exitFeeWallet) = IFarmFactory(_factory).feePercentageInfo();
        // pay the fees!
        if (exitFeePercentage > 0) {
            uint256 fee = (lpData.amount * ((exitFeePercentage * 1e18) / IFarmMain(_farmMainAddress).ONE_HUNDRED())) / 1e18;
            _safeTransfer(_pinnedSetupInfo.liquidityPoolTokenAddress, exitFeeWallet, fee);
            lpData.amount = lpData.amount - fee;
        }
        // check if the user wants to unwrap its pair or not
        if (unwrapPair) {
            // remove liquidity using AMM
            _safeApprove(lpData.liquidityPoolAddress, _pinnedSetupInfo.ammPlugin, lpData.amount);
            IAMM(_pinnedSetupInfo.ammPlugin).removeLiquidity(lpData);
        } else {
            // send back the liquidity pool token amount without the fee
            _safeTransfer(lpData.liquidityPoolAddress, lpData.receiver, lpData.amount);
        }
        // delete the farming position after the withdraw
        if (remainingLiquidity == 0) {
            delete _positions[positionId];
        } else {
            // update the creation block and amount
            farmingPosition.liquidityPoolTokenAmount = remainingLiquidity;
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
}