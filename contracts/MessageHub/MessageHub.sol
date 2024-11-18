// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "./MessageHubBase.sol";

contract MessageHub is MessageHubBase, MessageHubInterfaces {

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
        address recipient,
        uint amount
    ) external payable override {

        bytes memory payload = abi.encode(recipient, amount);
        _sendMessageInternal(sender, payload);
    }

    function _execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) internal override {

        bytes4 selector = bytes4(payload[: 4]);

        if (selector == KErc20CrossChainInterface.mint.selector) {
            (, address sender, uint amount) = abi.decode(payload, (bytes4, address, uint));
            KErc20CrossChainInterface(kToken).mint(sender, amount);
        } else if (selector == KErc20CrossChainInterface.repayBorrow.selector) {
            (, address sender, uint amount) = abi.decode(payload, (bytes4, address, uint));
            KErc20CrossChainInterface(kToken).repayBorrow(sender, amount);
        } else if (selector == KErc20CrossChainInterface.repayBorrowBehalf.selector) {
            (, address sender, address borrower, uint amount) = abi.decode(payload, (bytes4, address, address, uint));
            KErc20CrossChainInterface(kToken).repayBorrowBehalf(sender, borrower, amount);
        } else {
            revert("Unknown function selector");
        }
    }

}
