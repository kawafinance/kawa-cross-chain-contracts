// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import {KTokenInterface} from "./KTokenInterface.sol";
import {PriceOracleInterface} from "./PriceOracleInterface.sol";

contract PythOracle is PriceOracleInterface {
    IPyth public immutable pyth;
    address public admin;

    bool public constant override isPriceOracle = true;
    address internal constant ETH_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Pyth USD-denominated feeds store answers at 8 decimals
    uint256 internal constant USD_DECIMAL = 8;

    // Stores pyth oracle price Id of the particular token
    mapping(address => bytes32) public pythPriceIds;

    // Mapping to store direct price by token address
    mapping(address => uint256) public directPrices;

    constructor(address pythContract) {
        admin = msg.sender;
        pyth = IPyth(pythContract);
    }

    /**
     * @dev returns price of cToken underlying
     * @param kToken address of the kToken
     * @return scaled price of the underlying
     */
    function getUnderlyingPrice(
        KTokenInterface kToken
    ) external view override returns (uint256) {
        string memory symbol = kToken.symbol();
//        if (compareStrings(symbol, "kETH")) {
//            return getOraclePrice(ETH_ADDRESS);
//        } else {
            return getPrice(address(kToken));
//        }
    }

    /**
     * @dev returns price of token
     * @param kToken address of the kToken
     * @return price scaled price of the token
     */
    function getPrice(address kToken) public view returns (uint256 price) {
        address token = address(KTokenInterface(kToken).underlying());

        uint256 directPrice = directPrices[token];
        if (directPrice > 0) {
            price = directPrice;
        } else {
            price = getOraclePrice(token);
        }

        uint256 decimalDelta = uint256(18) - KTokenInterface(token).decimals();
        // Ensure that we don't multiply the result by 0
        if (decimalDelta > 0) {
            price = price * (10 ** decimalDelta);
        }
    }

    /**
     * @param token underlying address of cToken
     * @return price underlying price in 18 decimal places
     */
    function getOraclePrice(
        address token
    ) internal view returns (uint256 price) {
        PythStructs.Price memory _price = pyth.getPriceNoOlderThan(
            pythPriceIds[token],
            24 * 60 * 60
        );
        price = uint256(uint64(_price.price));

        uint decimalDelta = uint256(18) - USD_DECIMAL;
        if (decimalDelta > 0) {
            price = price * (10 ** decimalDelta);
        }
    }

    /**
     * @dev set price of the token directly, only in case if there is no feed
     * @param token address of the underlying token
     * @param price underlying price in 18 decimal places
     */
    function setDirectPrice(address token, uint256 price) external onlyAdmin {
        directPrices[token] = price;
    }

    function updateAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
    }

    function updatePythPriceIds(
        address[] memory _tokens,
        bytes[] memory _ids
    ) external onlyAdmin {
        for (uint256 i = 0; i < _tokens.length; i++) {
            pythPriceIds[_tokens[i]] = bytes32(_ids[i]);
        }
    }

    function compareStrings(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) ==
            keccak256(abi.encodePacked((b))));
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin may call");
        _;
    }
}
