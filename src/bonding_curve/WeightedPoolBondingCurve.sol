// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IBondingCurve} from "../../interface/IBondingCurve.sol";

contract WeightedPoolBondingCurve is IBondingCurve {
    // Weight of the weighted pool in BPS, e.g. 7500 for 75%
    uint256 public immutable weight;

    constructor(uint256 _weight) {
        weight = _weight;
    }

    function getPriceAndFee(
        uint256 shareCountBondingCurve,
        uint256 remainingShareCountBondingCurve,
        uint256 amount
    ) external view override returns (uint256 price, uint256 fee) {
        // outputPrice = balance_token[market] * (  1 - ( shareCount / shareCount + amount) ^ (weight / (1 - weight)  )
        uint256 shareCount = shareCountBondingCurve + remainingShareCountBondingCurve;
        uint256 startingPrice = (shareCount * 1e18) /
            remainingShareCountBondingCurve**(weight / (10_000 - weight)) -
            1e18;
        uint256 endPrice = (shareCount * 1e18) /
            (remainingShareCountBondingCurve - amount)**(weight / (10_000 - weight)) -
            1e18;
        price = endPrice - startingPrice;
        fee = (getFee(shareCount) * price) / 1e18;
    }

    function getFee(uint256 shareCount) public pure override returns (uint256) {
        return 1e17; // 0.1
    }
}
