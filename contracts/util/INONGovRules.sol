// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@ethereansos/swissknife/contracts/factory/model/IFactory.sol";

interface INONGovRules is IFactory {

    function feeInfo() external view returns(address operator, uint256 feePercentageForTransacted, address feeReceiver, address tokenToTransferOrBurnAddressInCreation, uint256 transferOrBurnAmountInCreation, address transferOrBurnReceiverInCreation, address tokenToTransferOrBurnAddressInApplication, uint256 transferOrBurnAmountInApplication, address transferOrBurnReceiverInApplication);

    function payFee(address sender, address tokenAddress, uint256 value, bytes calldata permitSignature) external payable returns (uint256 feePaid);
    function burnOrTransferToken(address sender, bytes calldata permitSignature) external payable returns(uint256 amountTransferedOrBurnt);
}