// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

library AddressBytes32Utils {
    function toAddress(bytes32 data) internal pure returns (address addr) {
        assembly {
            addr := and(data, 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }

    function toBytes32(address addr) internal pure returns (bytes32 result) {
        assembly {
            result := addr
        }
    }
}
