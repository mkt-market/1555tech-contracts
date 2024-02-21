
// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;
interface IBondingCurve {
    /// @notice Returns the price and fee multipliers for buying or selling a given number of shares.
    /// @param shareCountBondingCurve The current number of shares in the bonding curve.
    /// @param remainingShareCountBondingCurve The number of remaining shares in the bonding curve.
    /// @param amount The number of shares to buy or sell.
    function getPriceAndFee(uint256 shareCountBondingCurve, uint256 remainingShareCountBondingCurve, uint256 amount) external view returns (uint256 price, uint256 fee);

    /// @notice Returns the fee for buying or selling one share when the market has a given number of shares in circulation.
    /// @param shareCount The number of shares in circulation.
    function getFee(uint256 shareCount) external returns (uint256 fee);
}