// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IFraxLend {
    function deposit(uint256, address) external;

    function redeem(uint256, address, address) external;

    function balanceOf(address) external view returns (uint256);

    function addInterest() external;

    /// @notice The ```toAssetAmount``` function converts a given number of shares to an asset amount
    /// @param _shares Shares of asset (fToken)
    /// @param _roundUp Whether to round up after division
    /// @return The amount of asset
    function toAssetAmount(
        uint256 _shares,
        bool _roundUp
    ) external view returns (uint256);

    /// @notice The ```toAssetShares``` function converts a given asset amount to a number of asset shares (fTokens)
    /// @param _amount The amount of asset
    /// @param _roundUp Whether to round up after division
    /// @return The number of shares (fTokens)
    function toAssetShares(
        uint256 _amount,
        bool _roundUp
    ) external view returns (uint256);
}
