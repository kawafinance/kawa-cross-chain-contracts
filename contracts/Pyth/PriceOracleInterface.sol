// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "./KTokenInterface.sol";

interface PriceOracleInterface {
    /// @notice Indicator that this is a PriceOracle contract (for inspection)
    function isPriceOracle() external returns (bool);

    /**
     * @notice Get the underlying price of a kToken asset
     * @param kToken The kToken to get the underlying price of
     * @return The underlying asset price mantissa (scaled by 1e18).
     *  Zero means the price is unavailable.
     */
    function getUnderlyingPrice(
        KTokenInterface kToken
    ) external view returns (uint);
}
