// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "./BaseAdapter.sol";
import { OApp, Origin, MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

contract AdapterLayerZero is BaseAdapter, OApp {

    using OptionsBuilder for bytes;

    bytes32 public peerContract;
    uint32 public peerChain;

    event NewPeerContract(
        bytes32 oldPeerContract,
        bytes32 newPeerContract
    );

    event NewPeerChain(
        uint32 oldPeerChain,
        uint32 newPeerChain
    );

    event LayerZeroMessageSent(
        address sender,
        bytes payload
    );

    event LayerZeroMessageReceived(
        bytes32 guid,
        uint32 sourceChain,
        bytes32 sourceAddress,
        bytes payload
    );


    constructor(
        address centralHub_,
        bytes32 peerContract_,
        uint32 peerChain_,
        address endpoint_
    )
    BaseAdapter(centralHub_)
    OApp(endpoint_, msg.sender)
    {
        setPeer(peerChain_, peerContract_);
    }

    function _setPeerContract(bytes32 peerContract_) internal {
        bytes32 oldPeerContract = peerContract;
        peerContract = peerContract_;

        emit NewPeerContract(oldPeerContract, peerContract);
    }

    function _setPeerChain(uint32 peerChain_) internal {
        uint32 oldPeerChain = peerChain;
        peerChain = peerChain_;

        emit NewPeerChain(oldPeerChain, peerChain);
    }

    /**
     * @notice Sets the peer address (OApp instance) for a corresponding endpoint.
     * @param _peerChain The endpoint ID.
     * @param _peerContract The address of the peer to be associated with the corresponding endpoint.
     *
     * @dev Only the owner/admin of the OApp can call this function.
     * @dev Indicates that the peer is trusted to send LayerZero messages to this OApp.
     * @dev Set this to bytes32(0) to remove the peer address.
     * @dev Peer is a bytes32 to accommodate non-evm chains.
     */
    function setPeer(uint32 _peerChain, bytes32 _peerContract) public override onlyOwner {
        _setPeerChain(_peerChain);
        _setPeerContract(_peerContract);
        _setPeer(_peerChain, _peerContract);
    }

    function calculateGas(
        bytes memory payload
    ) external view override returns (uint cost) {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(uint128(gasLimit), 0);
        MessagingFee memory messagingFee = _quote(peerChain, payload, options, false);
        cost = messagingFee.nativeFee;
    }

    /**
     * @notice Sends a message from the source to destination chain.
     * @param sender The user initiating the action
     * @param payload The action payload.
     */
    function sendMessage(
        address sender,
        bytes calldata payload
    ) external payable override {
        uint cost = this.calculateGas(payload);
        _requireSenderCost(cost);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(uint128(gasLimit), 0);
        _lzSend(
            peerChain,
            payload,
            options,
            MessagingFee(cost, 0),
            payable(sender)
        );

        emit LayerZeroMessageSent(sender, payload);
    }

    /**
     * @dev Called when data is received from the protocol. It overrides the equivalent function in the parent contract.
     * Protocol messages are defined as packets, comprised of the following parameters.
     * @param _origin A struct containing information about where the packet came from.
     * @param _guid A global unique identifier for tracking the packet.
     * @param payload Encoded message.
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata payload,
        address /*executor*/,  // Executor address as specified by the OApp.
        bytes calldata /*_extraData*/  // Any extra data or options to trigger on receipt.
    ) internal override {

        CentralHubInterfae(centralHub).receiveMessage(payload);
        emit LayerZeroMessageReceived(_guid, _origin.srcEid, _origin.sender, payload);
    }
}
