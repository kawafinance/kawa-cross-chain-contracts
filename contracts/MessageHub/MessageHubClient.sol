// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "./MessageHubBase.sol";

contract MessageHubClient is MessageHubBase, MessageHubClientInterface {
    constructor(
        address kToken_,
        address gateway_,
        address gasReceiver_,
        address clientContract_,
        string memory clientChain_
    ) MessageHubBase(
    kToken_,
    gateway_,
    gasReceiver_,
    clientContract_,
    clientChain_
    )
    {}

    function sendMessage(
        address sender,
        bytes memory payload
    ) external payable override {
        _sendMessageInternal(sender, payload);
    }

    function _execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) internal override {
        (address recipient, uint amount) = abi.decode(payload, (address, uint));
        KClientInterface(kToken).releaseETH(payable(recipient), amount);
    }
}
