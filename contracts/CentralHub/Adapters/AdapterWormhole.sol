// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "./BaseAdapter.sol";
import "../../libs/AddressBytes32Utils.sol";
import "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";

contract AdapterWormhole is BaseAdapter, IWormholeReceiver {

    using AddressBytes32Utils for bytes32;
    using AddressBytes32Utils for address;

    bytes32 public peerContract;
    uint16 public peerChain;
    uint16 public thisChain;
    address public wormholeRelayer;

    event NewPeerContract(
        bytes32 oldPeerContract,
        bytes32 newPeerContract
    );

    event NewPeerChain(
        uint16 oldPeerChain,
        uint16 newPeerChain
    );

    event NewWormholeRelayer(
        address oldWormholeRelayer,
        address newWormholeRelayer
    );

    event WormholeMessageSent(
        address sender,
        bytes payload
    );

    event WormholeMessageReceived(
        bytes32 commandId,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes payload
    );

    constructor(
        address centralHub_,
        bytes32 peerContract_,
        uint16 peerChain_,
        uint16 thisChain_,
        address wormholeRelayer_
    )
    BaseAdapter(centralHub_)
    {
        peerContract = peerContract_;
        peerChain = peerChain_;
        thisChain = thisChain_;
        wormholeRelayer = wormholeRelayer_;
    }

    function _setPeerContract(bytes32 peerContract_) external onlyOwner {
        peerContract = peerContract_;
    }

    function _setPeerChain(uint16 peerChain_) external onlyOwner {
        peerChain = peerChain_;
    }

    function _setThisChain(uint16 thisChain_) external onlyOwner {
        thisChain = thisChain_;
    }

    function _setWormholeRelayer(address wormholeRelayer_) external onlyOwner {
        wormholeRelayer = wormholeRelayer_;
    }

    function getPeerContract() external view returns (address) {
        return peerContract.toAddress();
    }

    function calculateGas(
        bytes memory payload,
        uint gasLimit
    ) external view override returns (uint cost) {
        (cost,) = IWormholeRelayer(wormholeRelayer).quoteEVMDeliveryPrice(
            peerChain,
            0,
            gasLimit
        );
    }

    function sendMessage(
        address sender,
        bytes calldata payload
    ) external payable override {

        uint cost = this.calculateGas('', 600000);
        _requireSenderCost(cost);

        IWormholeRelayerSend(wormholeRelayer).sendPayloadToEvm{value: cost}(
            peerChain,
            peerContract.toAddress(),
            payload, // Payload contains the message and sender address
            0, // No receiver value needed
            600000, // Gas limit for the transaction
            thisChain,
            sender
        );

        if (msg.value - cost > 0) {
            _sendEth(payable(sender), msg.value - cost);
        }
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory, // additional VAAs (optional, not needed here)
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 // delivery hash
    ) public payable override {
//        require(msg.sender == address(wormholeRelayer), "Wormhole:Only the relayer can call this function");
//        require(peerContract == sourceAddress, "Wormhole:Unauthorized sourceAddress");
//        require(peerChain == sourceChain, "Wormhole:Unauthorized sourceChain");

        CentralHubInterfae(centralHub).receiveMessage(payload);

    }

}