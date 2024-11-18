// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "./KErc20Delegate.sol";

interface KLike {
    function delegate(address delegatee) external;
}

/**
 * @title Kawa's KLikeDelegate Contract
 * @notice KTokens which can 'delegate votes' of their underlying ERC-20
 * @author Kawa
 */
contract KLikeDelegate is KErc20Delegate {
    /**
     * @notice Construct an empty delegate
     */
    constructor() KErc20Delegate() {}

    /**
     * @notice Admin call to delegate the votes of the Kawa-like underlying
     * @param kLikeDelegatee The address to delegate votes to
     */
    function _delegateMLikeTo(address kLikeDelegatee) external {
        require(
            msg.sender == admin,
            "only the admin may set the Kawa-like delegate"
        );
        KLike(underlying).delegate(kLikeDelegatee);
    }
}
