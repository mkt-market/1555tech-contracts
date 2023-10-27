
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;
interface IBondingCurve {
    function getBuyPriceAndFee(uint256 shareCount, uint256 amount) external returns (uint256 price, uint256 fee);

    function getSellPriceAndFee(uint256 shareCount, uint256 amount) external returns (uint256 price, uint256 fee);

    function getFee() external returns (uint256 fee);
}