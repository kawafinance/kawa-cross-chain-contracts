// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "./BaseAdapter.sol";
import "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";
import "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";

contract AdapterAxelar is BaseAdapter, AxelarExecutable {

    string public peerContract;
    string public peerChain;
    IAxelarGasService public gasReceiver;

    event NewPeerContract(
        string oldPeerContract,
        string newPeerContract
    );

    event NewPeerChain(
        string oldPeerChain,
        string newPeerChain
    );

    event NewAxelarGasReceiver(
        address oldAxelarGasReceiver,
        address newAxelarGasReceiver
    );

    event AxelarMessageSent(
        address sender,
        bytes payload
    );

    event AxelarMessageReceived(
        bytes32 commandId,
        string sourceChain,
        string sourceAddress,
        bytes payload
    );

    constructor(
        address centralHub_,
        string memory peerContract_,
        string memory peerChain_,
        address gateway_,
        address gasReceiver_
    )
    BaseAdapter(centralHub_)
    AxelarExecutable(gateway_)
    {
        peerContract = peerContract_;
        peerChain = peerChain_;
        gasReceiver = IAxelarGasService(gasReceiver_);
    }

    function _setPeerContract(string memory peerContract_) external onlyOwner {
        string memory oldPeerContract = peerContract;
        peerContract = peerContract_;

        emit NewPeerContract(oldPeerContract, peerContract);
    }

    function _setPeerChain(string memory peerChain_) external onlyOwner {
        string memory oldPeerChain = peerChain;
        peerChain = peerChain_;

        emit NewPeerContract(oldPeerChain, peerChain);
    }

    function _setAxelarGasReceiver(address gasReceiver_) external onlyOwner {
        address oldGasReceiver = address(gasReceiver);
        gasReceiver = IAxelarGasService(gasReceiver_);

        emit NewAxelarGasReceiver(oldGasReceiver, address(gasReceiver));
    }

    function calculateGas(
        bytes memory payload
    ) external view override returns (uint cost) {

        cost = gasReceiver.estimateGasFee(
            peerChain,
            peerContract,
            payload,
            gasLimit,
            ""
        );
    }

    function sendMessage(
        address sender,
        bytes calldata payload
    ) external payable override {

        uint cost = this.calculateGas(payload);
        _requireSenderCost(cost);

        gasReceiver.payNativeGasForContractCall{value: cost}(
            address(this),
            peerChain,
            peerContract,
            payload,
            sender
        );

        gateway().callContract(peerChain, peerContract, payload);
        if (msg.value - cost > 0) {
            _sendEth(payable(sender), msg.value - cost);
        }

        emit AxelarMessageSent(sender, payload);
    }

    function _execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) internal override {
        require(
            keccak256(abi.encodePacked(peerContract)) == keccak256(abi.encodePacked(sourceAddress)),
            "Axelar:Unauthorized sourceAddress"
        );
        require(
            keccak256(abi.encodePacked(peerChain)) == keccak256(abi.encodePacked(sourceChain)),
            "Axelar:Unauthorized sourceChain"
        );
        CentralHubInterfae(centralHub).receiveMessage(payload);

        emit AxelarMessageReceived(commandId, sourceChain, sourceAddress, payload);
    }
}
