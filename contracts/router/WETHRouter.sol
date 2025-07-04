// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {WETH9} from "./IWETH.sol";
import {KErc20} from "../KErc20.sol";

/// @notice WETH router for depositing raw ETH into Kawa by wrapping into WETH then calling mint
/// allows for a single transaction to remove ETH from Kawa
contract WETHRouter {
    using SafeERC20 for IERC20;

    /// @notice The WETH9 contract
    WETH9 public immutable weth;

    /// @notice The kToken contract
    KErc20 public immutable kToken;

    /// @notice construct the WETH router
    /// @param _weth The WETH9 contract
    /// @param _kToken The kToken contract
    constructor(WETH9 _weth, KErc20 _kToken) {
        weth = _weth;
        kToken = _kToken;
        _weth.approve(address(_kToken), type(uint256).max);
    }

    /// @notice Deposit ETH into the Kawa protocol
    /// @param recipient The address to receive the kToken
    function mint(address recipient) external payable {
        weth.deposit{value: msg.value}();

        require(kToken.mint(msg.value) == 0, "WETHRouter: mint failed");

        IERC20(address(kToken)).safeTransfer(
            recipient,
            kToken.balanceOf(address(this))
        );
    }

    /// @notice repay borrow using raw ETH with the most up to date borrow balance
    /// @dev all excess ETH will be returned to the sender
    /// @param borrower to repay on behalf of
    function repayBorrowBehalf(address borrower) public payable {
        uint256 received = msg.value;
        uint256 borrows = kToken.borrowBalanceCurrent(borrower);

        if (received > borrows) {
            weth.deposit{value: borrows}();

            require(
                kToken.repayBorrowBehalf(borrower, borrows) == 0,
                "WETHRouter: repay borrow behalf failed"
            );

            (bool success, ) = msg.sender.call{value: address(this).balance}(
                ""
            );
            require(success, "WETHRouter: ETH transfer failed");
        } else {
            weth.deposit{value: received}();

            require(
                kToken.repayBorrowBehalf(borrower, received) == 0,
                "WETHRouter: repay borrow behalf failed"
            );
        }
    }

    receive() external payable {
        require(msg.sender == address(weth), "WETHRouter: not weth"); // only accept ETH via fallback from the WETH contract
    }
}
