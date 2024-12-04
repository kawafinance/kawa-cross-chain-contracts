// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "./MessageInterfaces.sol";
import "../KTokenInterfaces.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// todo make this upgradable
contract CentralHub is CentralHubInterfae, Ownable {
    address public kToken;
    address[] public adapters;

    event NewKToken(
        address oldKToken,
        address newKToken
    );

    event NewAdapter(address newAdapter);

    event RemoveAdapter(address removedAdapter);

    constructor(address kToken_){
        kToken = kToken_;
    }

    function _setKToken(
        address kToken_
    ) external onlyOwner {
        address oldKToken = kToken;
        kToken = kToken_;
        emit NewKToken(oldKToken, kToken);
    }

    function _addAdapter(
        address adapter
    ) external onlyOwner {
        require(!_isAdapterExists(adapter), "Adapter already exists");
        adapters.push(adapter);
        emit NewAdapter(adapter);
    }

    function _removeAdapter(
        address adapter
    ) external onlyOwner {
        uint256 index = adapters.length;
        for (uint256 i = 0; i < adapters.length; i++) {
            if (adapters[i] == adapter) {
                index = i;
                break;
            }
        }

        require(index < adapters.length, "Address not found");

        adapters[index] = adapters[adapters.length - 1];
        adapters.pop();
        emit RemoveAdapter(adapter);
    }

    function sendMessage(
        address sender,
        bytes calldata payload
    ) external payable override {
        require(msg.sender == kToken, "Only market can send messages");

        for (uint256 i = 0; i < adapters.length; i++) {
            MessageInterface(adapters[i]).sendMessage{value: msg.value}(sender, payload);
        }
    }

    function receiveMessage(
        bytes calldata payload
    ) external override onlyAdapters {
        _executeAction(payload);
    }

    function calculateGas(
        bytes calldata payload,
        uint gasLimit
    ) external view override returns (uint cost){
        cost = 0;
        for (uint256 i = 0; i < adapters.length; i++) {
            cost += MessageInterface(adapters[i]).calculateGas(payload, gasLimit);
        }
    }

    function _executeAction(bytes calldata payload) internal {
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
        } else if (selector == KClientInterface.releaseETH.selector) {
            (, address recipient, uint amount) = abi.decode(payload, (bytes4, address, uint));
            KClientInterface(kToken).releaseETH(payable(recipient), amount);
        } else {
            revert("Unknown function selector");
        }
    }

    function _isAdapterExists(address adapter) internal view returns (bool) {
        for (uint256 i = 0; i < adapters.length; i++) {
            if (adapters[i] == adapter) {
                return true;
            }
        }
        return false;
    }

    modifier onlyAdapters() {
        bool isAllowed = false;
        for (uint256 i = 0; i < adapters.length; i++) {
            if (adapters[i] == msg.sender) {
                isAllowed = true;
                break;
            }
        }
        require(isAllowed, "Not an adapter");
        _;
    }
}
