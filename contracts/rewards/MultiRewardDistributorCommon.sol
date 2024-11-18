// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "../KToken.sol";

// The commonly structures and events for the MultiRewardDistributor
interface MultiRewardDistributorCommon {
    struct MarketConfig {
        // The owner/admin of the emission config
        address owner;
        // The emission token
        address emissionToken;
        // Scheduled to end at this time
        uint endTime;
        // Supplier global state
        uint224 supplyGlobalIndex;
        uint32 supplyGlobalTimestamp;
        // Borrower global state
        uint224 borrowGlobalIndex;
        uint32 borrowGlobalTimestamp;
        uint supplyEmissionsPerSec;
        uint borrowEmissionsPerSec;
    }

    struct MarketEmissionConfig {
        MarketConfig config;
        mapping(address => uint) supplierIndices;
        mapping(address => uint) supplierRewardsAccrued;
        mapping(address => uint) borrowerIndices;
        mapping(address => uint) borrowerRewardsAccrued;
    }

    struct RewardInfo {
        address emissionToken;
        uint totalAmount;
        uint supplySide;
        uint borrowSide;
    }

    struct IndexUpdate {
        uint224 newIndex;
        uint32 newTimestamp;
    }

    struct MTokenData {
        uint kTokenBalance;
        uint borrowBalanceStored;
    }

    struct RewardWithMToken {
        address kToken;
        RewardInfo[] rewards;
    }

    // Global index updates
    event GlobalSupplyIndexUpdated(
        KToken kToken,
        address emissionToken,
        uint newSupplyIndex,
        uint32 newSupplyGlobalTimestamp
    );
    event GlobalBorrowIndexUpdated(
        KToken kToken,
        address emissionToken,
        uint newIndex,
        uint32 newTimestamp
    );

    // Reward Disbursal
    event DisbursedSupplierRewards(
        KToken indexed kToken,
        address indexed supplier,
        address indexed emissionToken,
        uint totalAccrued
    );
    event DisbursedBorrowerRewards(
        KToken indexed kToken,
        address indexed borrower,
        address indexed emissionToken,
        uint totalAccrued
    );

    // Admin update events
    event NewConfigCreated(
        KToken indexed kToken,
        address indexed owner,
        address indexed emissionToken,
        uint supplySpeed,
        uint borrowSpeed,
        uint endTime
    );
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);
    event NewEmissionCap(uint oldEmissionCap, uint newEmissionCap);
    event NewEmissionConfigOwner(
        KToken indexed kToken,
        address indexed emissionToken,
        address currentOwner,
        address newOwner
    );
    event NewRewardEndTime(
        KToken indexed kToken,
        address indexed emissionToken,
        uint currentEndTime,
        uint newEndTime
    );
    event NewSupplyRewardSpeed(
        KToken indexed kToken,
        address indexed emissionToken,
        uint oldRewardSpeed,
        uint newRewardSpeed
    );
    event NewBorrowRewardSpeed(
        KToken indexed kToken,
        address indexed emissionToken,
        uint oldRewardSpeed,
        uint newRewardSpeed
    );
    event FundsRescued(address token, uint amount);

    // Pause guardian stuff
    event RewardsPaused();
    event RewardsUnpaused();

    // Errors
    event InsufficientTokensToEmit(
        address payable user,
        address rewardToken,
        uint amount
    );
}
