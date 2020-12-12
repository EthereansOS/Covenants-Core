//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../amm-aggregator/common/AMMData.sol";
import "../amm-aggregator/common/IAMM.sol";

contract LiquidityMining {

    // tier struct
    struct Tier {
        address ammPlugin;
        address[] liquidityProviders;
        uint256 startBlock;
        uint256 endBlock;
        bool free;
        uint256 rewardPerSingleBlock;
        uint256 liquidityPercentage;
    }

    // factory address that will create clones of this contract
    address public FACTORY;
    // address of the owner of this contract
    address private _owner;
    // address of the reward token
    address private _rewardTokenAddress;
    // addresses of accepted tokens for mining
    address[] private _acceptedTokens;
    // contract whitelisted tiers array
    Tier[] private _whitelistedTiers;
    // whether the token is by mint or by reserve
    bool private _byMint;
    // max liquidity percentage per tier type
    uint256 private _freeTierLiquidityPercentage;
    uint256 private _lockedTierLiquidityPercentage;

    /** @dev creates the first instance of this contract that will be cloned from the _factory contract.
      * @param _factory address of the factory contract.
     */
    constructor(address _factory) {
        FACTORY = _factory;
    }

    /** @dev onlyFactory modifier used to check for unauthorized initializations. */
    modifier onlyFactory {
        require(msg.sender == FACTORY, "Unauthorized.");
        _;
    }

    /** @dev onlyOwner modifier used to check for unauthorized changes. */
    modifier onlyOwner {
        require(msg.sender == _owner, "Unauthorized.");
        _;
    }

    /** @dev function called by the factory contract to initialize a new clone.
      * @param owner liquidity mining contract owner (a wallet or an extension).
      * @param ownerInitData encoded call function of the owner (used from an extension).
      * @param rewardTokenAddress the address of the reward token.
      * @param acceptedTokens array containing all the accepted tokens.
      * @param byMint whether the rewardToken must be rewarded by minting or by reserve.
      * @param whitelistedTiers array containing all the whitelisted tiers.
      * @return success if the initialize function has ended properly.
     */
    function initialize(address owner, bytes memory ownerInitData, address rewardTokenAddress, address[] memory acceptedTokens, bool byMint, Tier[] memory whitelistedTiers, uint256 freeTierLiquidityPercentage, uint256 lockedTierLiquidityPercentage) public onlyFactory returns(bool) {
        require(
            _owner == address(0) && 
            _rewardTokenAddress == address(0) && 
            acceptedTokens.length > 0 && 
            _acceptedTokens.length == 0 && 
            whitelistedTiers.length > 0 && 
            _whitelistedTiers.length == 0 &&
            freeTierLiquidityPercentage + lockedTierLiquidityPercentage == 100,
            "Already initialized."
        );
        _owner = owner;
        _rewardTokenAddress = rewardTokenAddress;
        _acceptedTokens = acceptedTokens;
        _byMint = byMint;
        _whitelistedTiers = whitelistedTiers;
        _freeTierLiquidityPercentage = freeTierLiquidityPercentage;
        _lockedTierLiquidityPercentage = lockedTierLiquidityPercentage;
        if (keccak256(ownerInitData) != keccak256("")) {
            (bool result,) = _owner.call(ownerInitData);
            require(result, "Error while initializing owner.");
        }
        return true;
    }

    /** @dev allows the contract owner to update the whitelistedTiers.
      * @param whitelistedTiers new whitelisted tiers.
      * @param freeTierLiquidityPercentage new free tier liquidity percentage (or 0 to leave it as it is).
      * @param lockedTierLiquidityPercentage new locked tier liquidity percentage (or 0 to leave it as it is).
      */
    function updateTiersAndLiquidity(Tier[] memory whitelistedTiers, uint256 freeTierLiquidityPercentage, uint256 lockedTierLiquidityPercentage) public onlyOwner {
        require((freeTierLiquidityPercentage + lockedTierLiquidityPercentage == 0 || freeTierLiquidityPercentage + lockedTierLiquidityPercentage == 100) && whitelistedTiers.length > 0, "Invalid liquidity or tiers.");
        if (freeTierLiquidityPercentage != 0 || lockedTierLiquidityPercentage != 0) {
            _freeTierLiquidityPercentage = freeTierLiquidityPercentage;
            _lockedTierLiquidityPercentage = lockedTierLiquidityPercentage;
        }
        uint256 liquidity;
        for (uint256 i = 0; i < whitelistedTiers.length; i++) {
            liquidity += whitelistedTiers[i].liquidityPercentage;
            assert(liquidity == 100);
        }
        _whitelistedTiers = whitelistedTiers;
    }

    function stake(uint256 tierIndex, uint256 liquidityProviderIndex) public {
        Tier storage tier = _whitelistedTiers[tierIndex];
        require(tier.ammPlugin != address(0), "Invalid tier.");
        require(block.number >= tier.startBlock, "Staking not available.");
        require(block.number <= tier.endBlock, "Staking ended.");
        require(liquidityProviderIndex < tier.liquidityProviders.length, "Invalid liquidity provider.");
        IAMM amm = IAMM(tier.ammPlugin);
    }
}