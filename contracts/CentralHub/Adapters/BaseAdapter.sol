// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "../MessageInterfaces.sol";
import "../../libs/UintToStrUtils.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract BaseAdapter is MessageInterface, Ownable {

    using UintToStrUtils for uint256;

    address public centralHub;
    uint public gasLimit;

    event NewCentralHub(
        address oldCentralHub,
        address newCentralHub
    );

    event NewGasLimit(
        uint oldGasLimit,
        uint newGasLimit
    );

    constructor(address centralHub_)    {
        centralHub = centralHub_;
        gasLimit = 600000;
    }

    function _setCentralHub(
        address centralHub_
    ) external onlyOwner {
        address oldCentralHub = centralHub;
        centralHub = centralHub_;

        emit NewCentralHub(oldCentralHub, centralHub);
    }

    function _sendEth(
        address payable recipient,
        uint amount
    ) internal {
        (bool success,) = recipient.call{value: amount}("");
        require(success, "Refund  failed");
    }

    function _setGasLimit(
        uint gasLimit_
    ) external onlyOwner {
        uint oldGasLimit_ = gasLimit;
        gasLimit = gasLimit_;

        emit NewGasLimit(oldGasLimit_, gasLimit);
    }

    function _requireSenderCost(
        uint cost
    ) internal {
        require(msg.sender == centralHub, "Unauthorized");
        require(
            msg.value == cost,
            string(abi.encodePacked("Insufficient funds for cross-chain message. Sent: ", msg.value.uint2str(), " Required: ", cost.uint2str()))
        );
    }
}
