// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "forge-std/Script.sol";
import "../src/bonding_curve/LinearBondingCurve.sol";
import "../src/Market.sol";
import "../src/test/TestToken.sol";

contract DeploymentScript is Script {

    function setUp() public {}

    function run() public {
        Market market = Market(0xD7ed20eD2A70ba8EAA7F2D54b7FEaEbc4e05FD37);
        TestToken token = TestToken(0xA0E000057430d08269C882940aDC8842DED37eb3);
        token.mint(10000e18);
        (uint256 price, uint256 fee) = market.getBuyPrice(4, 5);
        console.logUint(price);
        console.logUint(fee);
        token.approve(address(market), price + fee);
        market.buy(4, 5, price);
    }
}
