// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";
import "@axelar-network/axelar-gmp-sdk-solidity/contracts/libs/AddressString.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MessageHubStorage {
    address public kToken;

    IAxelarGasService public gasReceiver;

    string public clientContract;
    string public clientChain;
}

abstract contract MessageHubInterfaces {

    function sendMessage(
        address sender,
        address recipient,
        uint amount
    ) external payable virtual;
}

abstract contract MessageHubClientInterface {

    function sendMessage(
        address sender,
        bytes memory payload
    ) external payable virtual;
}