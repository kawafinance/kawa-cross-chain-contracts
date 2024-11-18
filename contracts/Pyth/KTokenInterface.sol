// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

interface KTokenInterface {
    function underlying() external view returns (address);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}
