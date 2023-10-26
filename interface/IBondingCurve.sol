
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;
interface IBondingCurve {
    function getBuyPriceAndFee() external returns (uint256 price, uint256 fee);

    function getSellPriceAndFee() external returns (uint256 price, uint256 fee);

    function getFee() external returns (uint256 fee);
}