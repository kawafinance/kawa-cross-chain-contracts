// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

library UintToStrUtils {
    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        while (_i != 0) {
            k = k - 1;
            bstr[k] = bytes1(uint8(48 + uint256(_i % 10)));
            _i /= 10;
        }
        return string(bstr);
    }
}
