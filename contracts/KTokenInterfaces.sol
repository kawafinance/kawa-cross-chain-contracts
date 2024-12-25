// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "./ComptrollerInterface.sol";
import "./irm/InterestRateModel.sol";
import "./EIP20NonStandardInterface.sol";
import "./TokenErrorReporter.sol";

contract KTokenStorage {
    /// @dev Guard variable for re-entrancy checks
    bool internal _notEntered;

    /// @notice EIP-20 token name for this token
    string public name;

    /// @notice EIP-20 token symbol for this token
    string public symbol;

    /// @notice EIP-20 token decimals for this token
    uint8 public decimals;

    /// @notice Maximum borrow rate that can ever be applied (.0005% / block)
    uint internal constant borrowRateMaxMantissa = 0.0005e16;

    // @notice Maximum fraction of interest that can be set aside for reserves
    uint internal constant reserveFactorMaxMantissa = 1e18;

    /// @notice Administrator for this contract
    address payable public admin;

    /// @notice Pending administrator for this contract
    address payable public pendingAdmin;

    /// @notice Contract which oversees inter-kToken operations
    ComptrollerInterface public comptroller;

    /// @notice Model which tells what the current interest rate should be
    InterestRateModel public interestRateModel;

    // @notice Initial exchange rate used when minting the first KTokens (used when totalSupply = 0)
    uint internal initialExchangeRateMantissa;

    /// @notice Fraction of interest currently set aside for reserves
    uint public reserveFactorMantissa;

    /// @notice Block number that interest was last accrued at
    uint public accrualBlockTimestamp;

    /// @notice Accumulator of the total earned interest rate since the opening of the market
    uint public borrowIndex;

    /// @notice Total amount of outstanding borrows of the underlying in this market
    uint public totalBorrows;

    /// @notice Total amount of reserves of the underlying held in this market
    uint public totalReserves;

    /// @notice Total number of tokens in circulation
    uint public totalSupply;

    /// @notice Official record of token balances for each account
    mapping(address => uint) internal accountTokens;

    /// @notice Approved token transfer amounts on behalf of others
    mapping(address => mapping(address => uint)) internal transferAllowances;


    /**
     * @notice Container for borrow balance information
     * @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
     * @member interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint principal;
        uint interestIndex;
    }

    // @notice Mapping of account addresses to outstanding borrow balances
    mapping(address => BorrowSnapshot) internal accountBorrows;

    /// @notice Share of seized collateral that is added to reserves
    uint public protocolSeizeShareMantissa;
}

abstract contract KTokenInterface is KTokenStorage {
    /// @notice Indicator that this is a KToken contract (for inspection)
    bool public constant isKToken = true;

    /*** Market Events ***/

    /// @notice Event emitted when interest is accrued
    event AccrueInterest(
        uint cashPrior,
        uint interestAccumulated,
        uint borrowIndex,
        uint totalBorrows
    );

    /// @notice Event emitted when tokens are minted
    event Mint(address minter, uint mintAmount, uint mintTokens);

    /// @notice Event emitted when tokens are redeemed
    event Redeem(address redeemer, uint redeemAmount, uint redeemTokens);

    /// @notice Event emitted when underlying is borrowed
    event Borrow(
        address borrower,
        uint borrowAmount,
        uint accountBorrows,
        uint totalBorrows
    );

    /// @notice Event emitted when a borrow is repaid
    event RepayBorrow(
        address payer,
        address borrower,
        uint repayAmount,
        uint accountBorrows,
        uint totalBorrows
    );

    /// @notice Event emitted when a borrow is liquidated
    event LiquidateBorrow(
        address liquidator,
        address borrower,
        uint repayAmount,
        address kTokenCollateral,
        uint seizeTokens
    );

    /*** Admin Events ***/

    /// @notice Event emitted when pendingAdmin is changed
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /// @notice Event emitted when pendingAdmin is accepted, which means admin is updated
    event NewAdmin(address oldAdmin, address newAdmin);

    /// @notice Event emitted when comptroller is changed
    event NewComptroller(
        ComptrollerInterface oldComptroller,
        ComptrollerInterface newComptroller
    );

    /// @notice Event emitted when interestRateModel is changed
    event NewMarketInterestRateModel(
        InterestRateModel oldInterestRateModel,
        InterestRateModel newInterestRateModel
    );

    /// @notice Event emitted when the reserve factor is changed
    event NewReserveFactor(
        uint oldReserveFactorMantissa,
        uint newReserveFactorMantissa
    );

    /// @notice Event emitted when the protocol seize share is changed
    event NewProtocolSeizeShare(
        uint oldProtocolSeizeShareMantissa,
        uint newProtocolSeizeShareMantissa
    );

    /// @notice Event emitted when the reserves are added
    event ReservesAdded(
        address benefactor,
        uint addAmount,
        uint newTotalReserves
    );

    /// @notice Event emitted when the reserves are reduced
    event ReservesReduced(
        address admin,
        uint reduceAmount,
        uint newTotalReserves
    );

    /// @notice EIP20 Transfer event
    event Transfer(address indexed from, address indexed to, uint amount);

    /// @notice EIP20 Approval event
    event Approval(address indexed owner, address indexed spender, uint amount);

    /*** User Interface ***/

    function transfer(address dst, uint amount) external virtual returns (bool);
    function transferFrom(
        address src,
        address dst,
        uint amount
    ) external virtual returns (bool);
    function approve(
        address spender,
        uint amount
    ) external virtual returns (bool);
    function allowance(
        address owner,
        address spender
    ) external view virtual returns (uint);
    function balanceOf(address owner) external view virtual returns (uint);
    function balanceOfUnderlying(address owner) external virtual returns (uint);
    function getAccountSnapshot(
        address account
    ) external view virtual returns (uint, uint, uint, uint);
    function borrowRatePerTimestamp() external view virtual returns (uint);
    function supplyRatePerTimestamp() external view virtual returns (uint);
    function totalBorrowsCurrent() external virtual returns (uint);
    function borrowBalanceCurrent(
        address account
    ) external virtual returns (uint);
    function borrowBalanceStored(
        address account
    ) external view virtual returns (uint);
    function exchangeRateCurrent() external virtual returns (uint);
    function exchangeRateStored() external view virtual returns (uint);
    function getCash() external view virtual returns (uint);
    function accrueInterest() external virtual returns (uint);
    function seize(
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external virtual returns (uint);

    /*** Admin Functions ***/

    function _setPendingAdmin(
        address payable newPendingAdmin
    ) external virtual returns (uint);
    function _acceptAdmin() external virtual returns (uint);
    function _setComptroller(
        ComptrollerInterface newComptroller
    ) external virtual returns (uint);
    function _setReserveFactor(
        uint newReserveFactorMantissa
    ) external virtual returns (uint);
    function _reduceReserves(uint reduceAmount) external virtual returns (uint);
    function _setInterestRateModel(
        InterestRateModel newInterestRateModel
    ) external virtual returns (uint);
    function _setProtocolSeizeShare(
        uint newProtocolSeizeShareMantissa
    ) external virtual returns (uint);
}

contract KErc20Storage {
    /// @notice Underlying asset for this KToken
    address public underlying;
    /// @notice centralHub for this KToken
    address public centralHub;
}

abstract contract KErc20BaseInterface is KErc20Storage {

    /*** Admin Functions ***/

    function sweepToken(EIP20NonStandardInterface token) external virtual;
    function _addReserves(uint addAmount) external virtual returns (uint);
}

abstract contract KErc20Interface {
    /*** User Interface ***/

    function mint(uint mintAmount) external virtual returns (uint);
    function mintWithPermit(
        uint mintAmount,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual returns (uint);
    function repayBorrow(uint repayAmount) external virtual returns (uint);
    function repayBorrowBehalf(
        address borrower,
        uint repayAmount
    ) external virtual returns (uint);
    function redeem(uint redeemTokens) external virtual returns (uint);
    function redeemUnderlying(
        uint redeemAmount
    ) external virtual returns (uint);
    function borrow(uint borrowAmount) external virtual returns (uint);
    function liquidateBorrow(
        address borrower,
        uint repayAmount,
        KTokenInterface kTokenCollateral
    ) external virtual returns (uint);
}

abstract contract KErc20CrossChainInterface {
    /*** MessageHub Interface ***/

    function mint(
        address minter,
        uint mintAmount
    ) external virtual returns (uint);
    function repayBorrow(
        address payer,
        uint repayAmount
    ) external virtual returns (uint);
    function repayBorrowBehalf(
        address payer,
        address borrower,
        uint repayAmount
    ) external virtual returns (uint);
    function liquidateBorrow(
        address liquidator,
        address borrower,
        uint repayAmount,
        KTokenInterface kTokenCollateral
    ) external virtual returns (uint);

    /*** User Interface ***/

    function redeem(uint redeemTokens) external payable virtual returns (uint);
    function redeemUnderlying(
        uint redeemAmount
    ) external payable virtual returns (uint);
    function borrow(uint borrowAmount) external payable virtual returns (uint);

    /*** Admin Functions ***/

    function _setCentralHub(address newCentralHub) external virtual;

    /// @notice Event emitted when the message hub is changed
    event NewCentralHub(
        address oldCentralHub,
        address centralHub
    );
}

contract KDelegationStorage {
    /// @notice Implementation address for this contract
    address public implementation;
}

abstract contract KDelegatorInterface is KDelegationStorage {
    /// @notice Emitted when implementation is changed
    event NewImplementation(
        address oldImplementation,
        address newImplementation
    );

    /**
     * @notice Called by the admin to update the implementation of the delegator
     * @param implementation_ The address of the new implementation for delegation
     * @param allowResign Flag to indicate whether to call _resignImplementation on the old implementation
     * @param becomeImplementationData The encoded bytes data to be passed to _becomeImplementation
     */
    function _setImplementation(
        address implementation_,
        bool allowResign,
        bytes memory becomeImplementationData
    ) external virtual;
}

abstract contract KDelegateInterface is KDelegationStorage {
    /**
     * @notice Called by the delegator on a delegate to initialize it for duty
     * @dev Should revert if any issues arise which make it unfit for delegation
     * @param data The encoded bytes data for any initialization
     */
    function _becomeImplementation(bytes memory data) external virtual;

    /// @notice Called by the delegator on a delegate to forfeit its responsibility
    function _resignImplementation() external virtual;
}

contract KClientStorage {

    /// @notice MessageHub implementation's address
    address public centralHub;

    /// @notice Administrator for this contract
    address payable public admin;
}

abstract contract KClientInterface is KClientStorage {
    /*** User Interface ***/
    function mint(uint mintAmount) external payable virtual;
    function repayBorrow(uint repayAmount) external payable virtual;
    function repayBorrowBehalf(
        address borrower,
        uint repayAmount
    ) external payable virtual;
    function liquidateBorrow(
        address borrower,
        uint repayAmount,
        KTokenInterface kTokenCollateral
    ) external payable virtual;
    function releaseETH(
        address payable recipient,
        uint amount
    ) external virtual returns (bool);

    /// @notice Event emitted when tokens are minted
    event Mint(address minter, uint mintAmount, uint mintTokens);

    /// @notice Event emitted when a borrow is repaid
    event RepayBorrow(
        address payer,
        address borrower,
        uint repayAmount,
        uint accountBorrows,
        uint totalBorrows
    );

    /// @notice Event emitted when a borrow is liquidated
    event LiquidateBorrow(
        address liquidator,
        address borrower,
        uint repayAmount,
        address kTokenCollateral,
        uint seizeTokens
    );

    /// @notice Event emitted when the message hub is changed
    event NewCentralHub(
        address oldClientHub,
        address clientHub
    );
}
