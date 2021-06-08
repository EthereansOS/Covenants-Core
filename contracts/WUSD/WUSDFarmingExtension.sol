//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../farming/IFarmExtension.sol";
import "../farming/IFarmMain.sol";
import "../farming/util/DFOHub.sol";
import "./IWUSDExtensionController.sol";
import "./util/IERC20.sol";

contract WUSDFarmingExtension is IFarmExtension {

    string private constant FUNCTIONALITY_NAME = "manageFarming";

    uint256 public constant ONE_HUNDRED = 1e18;

    // wallet who has control on the extension
    address internal _doubleProxy;

    // mapping that contains all the farming contract linked to this extension
    address internal _farmingContract;

    // the reward token address linked to this farming contract
    address internal _rewardTokenAddress;

    address public wusdExtensionControllerAddress;

    uint256 public rewardCreditPercentage;

    FarmingSetupInfo[] private infoModels;
    uint256[] private rebalancePercentages;

    uint256 public lastCheck;
    uint256 public lastBalance;

    /** MODIFIERS */

    /** @dev farmingOnly modifier used to check for unauthorized transfers. */
    modifier farmingOnly() {
        require(msg.sender == _farmingContract, "Unauthorized");
        _;
    }

    /** @dev hostOnly modifier used to check for unauthorized edits. */
    modifier hostOnly() {
        require(_isFromDFO(msg.sender), "Unauthorized");
        _;
    }

    /** PUBLIC METHODS */

    function init(bool, address, address) public virtual override {
        revert("Method not allowed, use specific one instead");
    }

    function init(address host, address _wusdExtensionControllerAddress, FarmingSetupInfo[] memory farmingSetups, uint256[] memory _rebalancePercentages, uint256 _rewardCreditPercentage) public virtual {
        require(_farmingContract == address(0), "Already init");
        require(host != address(0), "blank host");
        _rewardTokenAddress = IFarmMain(_farmingContract = msg.sender)._rewardTokenAddress();
        _doubleProxy = host;
        wusdExtensionControllerAddress = _wusdExtensionControllerAddress;
        _setModels(farmingSetups, _rebalancePercentages);
        rewardCreditPercentage = _rewardCreditPercentage;
    }

    function _setModels(FarmingSetupInfo[] memory farmingSetups, uint256[] memory _rebalancePercentages) private {
        require(farmingSetups.length > 0 && (farmingSetups.length - 1) == _rebalancePercentages.length, "Invalid data");
        delete rebalancePercentages;
        delete infoModels;
        uint256 percentage = 0;
        for(uint256 i = 0; i < _rebalancePercentages.length; i++) {
            farmingSetups[i].renewTimes = 0;
            infoModels.push(farmingSetups[i]);
            percentage += _rebalancePercentages[i];
            rebalancePercentages.push(_rebalancePercentages[i]);
        }
        farmingSetups[farmingSetups.length - 1].renewTimes = 0;
        infoModels.push(farmingSetups[farmingSetups.length - 1]);
        require(percentage < ONE_HUNDRED, "More than one hundred");
    }

    /** @dev allows the DFO to update the double proxy address.
      * @param newDoubleProxy new double proxy address.
     */
    function setHost(address newDoubleProxy) public virtual override hostOnly {
        _doubleProxy = newDoubleProxy;
    }

    /** @dev method used to update the extension treasury.
     */
    function setTreasury(address) public virtual override hostOnly {
        revert("Impossibru!");
    }

    function setRewardCreditPercentage(uint256 _rewardCreditPercentage) public hostOnly {
        rewardCreditPercentage = _rewardCreditPercentage;
    }

    function data() view public virtual override returns(address farmingContract, bool byMint, address host, address treasury, address rewardTokenAddress) {
        return (_farmingContract, false, _doubleProxy, _getDFOWallet(), _rewardTokenAddress);
    }

    function models() public view returns(FarmingSetupInfo[] memory, uint256[] memory) {
        return (infoModels, rebalancePercentages);
    }

    /** @dev transfers the input amount to the caller farming contract.
      * @param amount amount of erc20 to transfer or mint.
     */
    function transferTo(uint256 amount) public virtual override farmingOnly {
        lastBalance -= amount;
        if(_rewardTokenAddress != address(0)) {
            return _safeTransfer(_rewardTokenAddress, _farmingContract, amount);
        }
        (bool result, ) = _farmingContract.call{value:amount}("");
        require(result, "ETH transfer failed.");
    }

    /** @dev transfers the input amount from the caller farming contract to the extension.
      * @param amount amount of erc20 to transfer back or burn.
     */
    function backToYou(uint256 amount) payable public virtual override farmingOnly {
        lastBalance += amount;
        if(_rewardTokenAddress != address(0)) {
            return _safeTransferFrom(_rewardTokenAddress, msg.sender, address(this), amount);
        }
        require(msg.value == amount, "invalid sent amount");
    }

    function flushTo(address[] memory tokenAddresses, uint256[] memory amounts, address receiver) public hostOnly {
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            if(tokenAddresses[i] == address(0)) {
                (bool result, ) = receiver.call{value:amounts[i]}("");
                require(result, "ETH transfer failed.");
            } else {
                _safeTransfer(tokenAddresses[i], receiver, amounts[i]);
            }
        }
    }

    /** @dev this function calls the liquidity mining contract with the given address and sets the given liquidity mining setups.*/
    function setFarmingSetups(FarmingSetupConfiguration[] memory farmingSetups) public override hostOnly {
        IFarmMain(_farmingContract).setFarmingSetups(farmingSetups);
    }

    function setWusdExtensionControllerAddress(address _wusdExtensionControllerAddress) public hostOnly {
        wusdExtensionControllerAddress = _wusdExtensionControllerAddress;
    }

    function setModels(FarmingSetupInfo[] memory farmingSetups, uint256[] memory _rebalancePercentages) public hostOnly {
        _setModels(farmingSetups, _rebalancePercentages);
    }

    function rebalanceRewardsPerBlock() public {
        uint256 lastRebalanceByCreditBlock = IWUSDExtensionController(wusdExtensionControllerAddress).lastRebalanceByCreditBlock();
        require(lastRebalanceByCreditBlock > 0 && lastRebalanceByCreditBlock != lastCheck, "Invalid block");
        lastCheck = lastRebalanceByCreditBlock;
        uint256 amount = _calculatePercentage(IERC20(_rewardTokenAddress).balanceOf(_getDFOWallet()), rewardCreditPercentage);
        IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).submit(FUNCTIONALITY_NAME, abi.encode(address(0), 0, true, _rewardTokenAddress, address(this), amount, false));
        uint256 totalBalance = IERC20(_rewardTokenAddress).balanceOf(address(this));
        uint256 balance = totalBalance - lastBalance;
        lastBalance = totalBalance;
        uint256 remainingBalance = balance;
        uint256 currentReward = 0;
        FarmingSetupConfiguration[] memory farmingSetups = new FarmingSetupConfiguration[](infoModels.length);
        uint256 i;
        for(i = 0; i < rebalancePercentages.length; i++) {
            infoModels[i].originalRewardPerBlock = (currentReward = _calculatePercentage(balance, rebalancePercentages[i])) / infoModels[i].blockDuration;
            remainingBalance -= currentReward;
            farmingSetups[i] = FarmingSetupConfiguration(
                true,
                false,
                0,
                infoModels[i]
            );
        }
        i = rebalancePercentages.length;
        infoModels[i].originalRewardPerBlock = remainingBalance / infoModels[i].blockDuration;
        farmingSetups[i] = FarmingSetupConfiguration(
            true,
            false,
            0,
            infoModels[i]
        );
        IFarmMain(_farmingContract).setFarmingSetups(farmingSetups);
    }

    /** PRIVATE METHODS */

    function _calculatePercentage(uint256 totalSupply, uint256 percentage) private pure returns(uint256) {
        return (totalSupply * ((percentage * 1e18) / ONE_HUNDRED)) / 1e18;
    }

    /** @dev this function returns the address of the functionality with the FUNCTIONALITY_NAME.
      * @return functionalityAddress functionality FUNCTIONALITY_NAME address.
     */
    function _getFunctionalityAddress() private view returns(address functionalityAddress) {
        (functionalityAddress,,,,) = IMVDFunctionalitiesManager(IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDFunctionalitiesManagerAddress()).getFunctionalityData(FUNCTIONALITY_NAME);
    }

    /** @dev this function returns the address of the wallet of the linked DFO.
      * @return linked DFO wallet address.
     */
    function _getDFOWallet() private view returns(address) {
        return IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDWalletAddress();
    }

    /** @dev this function returns true if the sender is an authorized DFO functionality, false otherwise.
      * @param sender address of the caller.
      * @return true if the call is from a DFO, false otherwise.
     */
    function _isFromDFO(address sender) private view returns(bool) {
        return IMVDFunctionalitiesManager(IMVDProxy(IDoubleProxy(_doubleProxy).proxy()).getMVDFunctionalitiesManagerAddress()).isAuthorizedFunctionality(sender);
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