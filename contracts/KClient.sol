// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;
import "./CentralHub/MessageInterfaces.sol";
import "./KTokenInterfaces.sol";


contract KClient is KClientInterface {

    /*** User Interface ***/

    function mint(uint mintAmount) external payable override {
        bytes memory payload = abi.encode(
            KErc20CrossChainInterface.mint.selector,
            msg.sender,
            mintAmount
        );
        MessageInterface(centralHub).sendMessage{value: msg.value - mintAmount}(
            msg.sender,
            payload
        );
    }

    function repayBorrow(uint repayAmount) external payable override {
        bytes memory payload = abi.encode(
            KErc20CrossChainInterface.repayBorrow.selector,
            msg.sender,
            repayAmount
        );
        MessageInterface(centralHub).sendMessage{value: msg.value - repayAmount}(
            msg.sender,
            payload
        );
    }

    function repayBorrowBehalf(
        address borrower,
        uint repayAmount
    ) external payable override {
        bytes memory payload = abi.encode(
            KErc20CrossChainInterface.repayBorrowBehalf.selector,
            msg.sender,
            borrower,
            repayAmount
        );
        MessageInterface(centralHub).sendMessage{value: msg.value - repayAmount}(
            msg.sender,
            payload
        );
    }

    function liquidateBorrow(
        address borrower,
        uint repayAmount,
        KTokenInterface kTokenCollateral
    ) external payable override {
        bytes memory payload = abi.encode(
            KErc20CrossChainInterface.liquidateBorrow.selector,
            msg.sender,
            borrower,
            repayAmount,
            kTokenCollateral
        );
        MessageInterface(centralHub).sendMessage{value: msg.value - repayAmount}(
            msg.sender,
            payload
        );
    }


    /*** CentralHub Interface ***/

    function releaseETH(
        address payable recipient,
        uint amount
    ) external override returns (bool){
        require(msg.sender == centralHub, "Unauthorized");
        (bool success,) = recipient.call{value: amount}("");
        return success;
    }

    /*** Admin Functions ***/

    function _setCentralHub(address newCentralHub) external returns (bool){
        require(msg.sender == admin, "Unauthorized");

        address oldCentralHub = centralHub;
        centralHub = newCentralHub;

        emit NewCentralHub(
            oldCentralHub,
            centralHub
        );

        return true;
    }

    receive() external payable {}
}