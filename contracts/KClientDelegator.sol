// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "./KTokenInterfaces.sol";

/**
 * @title Kawa's KClientDelegator.sol Contract
 * @notice KTokens which wrap an EIP-20 underlying and delegate to an implementation
 * @author Kawa
 */
contract KClientDelegator is KClientInterface, KDelegatorInterface {

    constructor(
        address messageHub_,
        address payable admin_,
        address implementation_,
        bytes memory becomeImplementationData
    ) {
        // Creator of the contract is admin during initialization
        admin = payable(msg.sender);

        // First delegate gets to set message hub to the delegator
        delegateTo(
            implementation_,
            abi.encodeWithSignature(
                "_setMessageHub(address)",
                messageHub_
            )
        );

        // New implementations always get set via the settor (post-initialize)
        _setImplementation(implementation_, false, becomeImplementationData);

        // Set the proper admin now that initialization is done
        admin = admin_;
    }

    /**
     * @notice Sender supplies assets into the market and receives kTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param mintAmount The amount of the underlying asset to supply
     */
    function mint(
        uint mintAmount
    ) external payable override {
//        bytes memory data =
        delegateToImplementation(
            abi.encodeWithSignature(
                "mint(uint256)",
                mintAmount
            )
        );
//        return abi.decode(data, (uint));
    }

    /**
     * @notice Sender repays their own borrow
     * @param repayAmount The amount to repay, or uint.max for the full outstanding amount
     */
    function repayBorrow(
        uint repayAmount
    ) external payable override {
//        bytes memory data =
        delegateToImplementation(
            abi.encodeWithSignature(
                "repayBorrow(uint256)",
                repayAmount
            )
        );
//        return abi.decode(data, (uint));
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param borrower the account with the debt being payed off
     * @param repayAmount The amount to repay, or uint.max for the full outstanding amount
     */
    function repayBorrowBehalf(
        address borrower,
        uint repayAmount
    ) external payable override {
//        bytes memory data =
        delegateToImplementation(
            abi.encodeWithSignature(
                "repayBorrowBehalf(address,uint256)",
                borrower,
                repayAmount
            )
        );
//        return abi.decode(data, (uint));
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this kToken to be liquidated
     * @param kTokenCollateral The market in which to seize collateral from the borrower
     * @param repayAmount The amount of the underlying borrowed asset to repay
     */
    function liquidateBorrow(
        address borrower,
        uint repayAmount,
        KTokenInterface kTokenCollateral
    ) external payable override {
//        bytes memory data =
        delegateToImplementation(
            abi.encodeWithSignature(
                "liquidateBorrow(address,uint256,address)",
                borrower,
                repayAmount,
                kTokenCollateral
            )
        );
//        return abi.decode(data, (uint));
    }

    function releaseETH(
        address payable recipient,
        uint amount
    ) external override returns (bool) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature(
                "releaseETH(address,uint256)",
                recipient,
                amount
            )
        );
        return abi.decode(data, (bool));
    }

    /*** Admin Functions ***/

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
    ) public override {
        require(
            msg.sender == admin,
            "KClientDelegator::_setImplementation: Caller must be admin"
        );

        if (allowResign) {
            delegateToImplementation(
                abi.encodeWithSignature("_resignImplementation()")
            );
        }

        address oldImplementation = implementation;
        implementation = implementation_;

        delegateToImplementation(
            abi.encodeWithSignature(
                "_becomeImplementation(bytes)",
                becomeImplementationData
            )
        );

        emit NewImplementation(oldImplementation, implementation);
    }

    /**
     * @notice Begins transfer of admin rights. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
     * @dev Admin function to begin change of admin. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
     * @param newPendingAdmin New pending admin.
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setPendingAdmin(
        address payable newPendingAdmin
    ) external returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                newPendingAdmin
            )
        );
        return abi.decode(data, (uint));
    }

    /**
   * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
     * @dev Admin function for pending admin to accept role and update admin
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _acceptAdmin() external returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("_acceptAdmin()")
        );
        return abi.decode(data, (uint));
    }

    function _setMessageHub(address newMessageHub) external returns (uint)  {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("_setMessageHub(address)", newMessageHub)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Internal method to delegate execution to another contract
     * @dev It returns to the external caller whatever the implementation returns or forwards reverts
     * @param callee The contract to delegatecall
     * @param data The raw data to delegatecall
     * @return The returned bytes from the delegatecall
     */
    function delegateTo(
        address callee,
        bytes memory data
    ) internal returns (bytes memory) {
        (bool success, bytes memory returnData) = callee.delegatecall(data);
        assembly {
            if eq(success, 0) {
                revert(add(returnData, 0x20), returndatasize())
            }
        }
        return returnData;
    }

    /**
     * @notice Delegates execution to the implementation contract
     * @dev It returns to the external caller whatever the implementation returns or forwards reverts
     * @param data The raw data to delegatecall
     * @return The returned bytes from the delegatecall
     */
    function delegateToImplementation(
        bytes memory data
    ) public returns (bytes memory) {
        return delegateTo(implementation, data);
    }

    /**
     * @notice Delegates execution to an implementation contract
     * @dev It returns to the external caller whatever the implementation returns or forwards reverts
     *  There are an additional 2 prefix uints from the wrapper returndata, which we ignore since we make an extra hop.
     * @param data The raw data to delegatecall
     * @return The returned bytes from the delegatecall
     */
    function delegateToViewImplementation(
        bytes memory data
    ) public view returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).staticcall(
            abi.encodeWithSignature("delegateToImplementation(bytes)", data)
        );
        assembly {
            if eq(success, 0) {
                revert(add(returnData, 0x20), returndatasize())
            }
        }
        return abi.decode(returnData, (bytes));
    }

    /**
     * @notice Delegates execution to an implementation contract
     * @dev It returns to the external caller whatever the implementation returns or forwards reverts
     */
    fallback() external payable {
        require(
            msg.value == 0,
            "KClientDelegator:fallback: cannot send value to fallback"
        );

        // delegate all other functions to current implementation
        (bool success,) = implementation.delegatecall(msg.data);

        assembly {
            let free_mem_ptr := mload(0x40)
            returndatacopy(free_mem_ptr, 0, returndatasize())

            switch success
            case 0 {
                revert(free_mem_ptr, returndatasize())
            }
            default {
                return (free_mem_ptr, returndatasize())
            }
        }
    }

}
