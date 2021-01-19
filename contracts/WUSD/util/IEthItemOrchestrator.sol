//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IEthItemOrchestrator {
    function createNative(bytes calldata modelInitPayload, string calldata ens)
        external
        returns (address newNativeAddress, bytes memory modelInitCallResponse);
}