// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {WethUnwrapper} from "./WethUnwrapper.sol";
import {KErc20Delegate} from "./KErc20Delegate.sol";

/**
 * @title Kawa's KWethDelegate.sol Contract
 * @notice KToken which wraps underlying ETH
 * @author Kawa
 */
contract KWethDelegate is KErc20Delegate {
    using SafeERC20 for IERC20;

    /// @notice the WETH unwrapper address
    address public immutable wethUnwrapper;

    /// @notice construct a new KWethDelegate.sol
    /// @param _wethUnwrapper the WETH Unwrapper address
    constructor(address _wethUnwrapper) {
        wethUnwrapper = _wethUnwrapper;
    }

    /// @notice transfer ETH underlying to the recipient
    /// first unwrap the WETH into raw ETH, then transfer
    /// @param to the recipient address
    /// @param amount the amount of ETH to transfer
    function doTransferOut(
        address payable to,
        uint256 amount
    ) internal virtual override {
        IERC20 weth = IERC20(underlying);

        weth.safeTransfer(wethUnwrapper, amount);
        WethUnwrapper(payable(wethUnwrapper)).send(to, amount); /// send to user through wethUnwrapper
    }
}
