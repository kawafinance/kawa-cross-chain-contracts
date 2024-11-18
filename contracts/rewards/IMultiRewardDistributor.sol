// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "../KToken.sol";
import "../ExponentialNoError.sol";
import "./MultiRewardDistributor.sol";

interface IMultiRewardDistributor is MultiRewardDistributorCommon {
    // Public views
    function getAllMarketConfigs(
        KToken _kToken
    ) external view returns (MarketConfig[] memory);
    function getConfigForMarket(
        KToken _kToken,
        address _emissionToken
    ) external view returns (MarketConfig memory);
    function getOutstandingRewardsForUser(
        address _user
    ) external view returns (RewardWithMToken[] memory);
    function getOutstandingRewardsForUser(
        KToken _kToken,
        address _user
    ) external view returns (RewardInfo[] memory);
    function getCurrentEmissionCap() external view returns (uint);

    // Administrative functions
    function _addEmissionConfig(
        KToken _kToken,
        address _owner,
        address _emissionToken,
        uint _supplyEmissionPerSec,
        uint _borrowEmissionsPerSec,
        uint _endTime
    ) external;
    function _rescueFunds(address _tokenAddress, uint _amount) external;
    function _setPauseGuardian(address _newPauseGuardian) external;
    function _setEmissionCap(uint _newEmissionCap) external;

    // Comptroller API
    function updateMarketSupplyIndex(KToken _kToken) external;
    function disburseSupplierRewards(
        KToken _kToken,
        address _supplier,
        bool _sendTokens
    ) external;
    function updateMarketSupplyIndexAndDisburseSupplierRewards(
        KToken _kToken,
        address _supplier,
        bool _sendTokens
    ) external;
    function updateMarketBorrowIndex(KToken _kToken) external;
    function disburseBorrowerRewards(
        KToken _kToken,
        address _borrower,
        bool _sendTokens
    ) external;
    function updateMarketBorrowIndexAndDisburseBorrowerRewards(
        KToken _kToken,
        address _borrower,
        bool _sendTokens
    ) external;

    // Pause guardian functions
    function _pauseRewards() external;
    function _unpauseRewards() external;

    // Emission schedule admin functions
    function _updateSupplySpeed(
        KToken _kToken,
        address _emissionToken,
        uint _newSupplySpeed
    ) external;
    function _updateBorrowSpeed(
        KToken _kToken,
        address _emissionToken,
        uint _newBorrowSpeed
    ) external;
    function _updateOwner(
        KToken _kToken,
        address _emissionToken,
        address _newOwner
    ) external;
    function _updateEndTime(
        KToken _kToken,
        address _emissionToken,
        uint _newEndTime
    ) external;
}
