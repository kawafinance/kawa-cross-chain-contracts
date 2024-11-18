// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "../KTokenInterfaces.sol";
import "./MessageHubInterfaces.sol";

abstract contract MessageHubBase is MessageHubStorage, AxelarExecutable, Ownable {
    using StringToAddress for string;
    using AddressToString for address;

    constructor(
        address kToken_,
        address gateway_,
        address gasReceiver_,
        address clientContract_,
        string memory clientChain_
    )
    AxelarExecutable(gateway_)
    {
        kToken = kToken_;
        gasReceiver = IAxelarGasService(gasReceiver_);
        clientContract = clientContract_.toString();
        clientChain = clientChain_;
    }

    function _setKToken(address kToken_) external onlyOwner {
        kToken = kToken_;
    }

    function _setAxelarGasReceiver(address gasReceiver_) external onlyOwner {
        gasReceiver = IAxelarGasService(gasReceiver_);
    }

    function _setClientContract(address clientContract_) external onlyOwner {
        clientContract = clientContract_.toString();
    }

    function _setClientChain(string memory clientChain_) external onlyOwner {
        clientChain = clientChain_;
    }

    function _sendEth(
        address payable recipient,
        uint amount
    ) internal {
        (bool success,) = recipient.call{value: amount}("");
        require(success, "Refund  failed");
    }

    function _sendMessageInternal(
        address sender,
        bytes memory payload
    ) internal {
        require(msg.sender == kToken, "Unauthorized");

        uint gas = gasReceiver.estimateGasFee(
            clientChain,
            clientContract,
            payload,
            2000,
            ""
        );

        require(msg.value >= gas, "Insufficient funds");

        gasReceiver.payNativeGasForContractCall{value: gas}(
            address(this),
            clientChain,
            clientContract,
            payload,
            sender
        );

        gateway().callContract(clientChain, clientContract, payload);
        if (msg.value - gas > 0) {
            _sendEth(payable(sender), msg.value - gas);
        }
    }

    function gasEstimate(
        bytes memory payload,
        uint gasLimit
    ) external view returns (uint gas) {

        gas = gasReceiver.estimateGasFee(
            clientChain,
            clientContract,
            payload,
            gasLimit,
            ""
        );
    }
}
