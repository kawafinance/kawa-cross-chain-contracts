// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

abstract contract MessageInterface {
    function sendMessage(
        address sender,
        bytes calldata payload
    ) external payable virtual;

    function calculateGas(
        bytes memory payload,
        uint gasLimit
    ) external view virtual returns (uint cost);
}

abstract contract CentralHubInterfae is MessageInterface {
    function receiveMessage(
        bytes calldata payload
    ) external virtual;
}