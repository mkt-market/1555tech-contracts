// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "forge-std/Script.sol";
import "../src/bonding_curve/LinearBondingCurve.sol";
import "../src/Market.sol";
import "../src/test/TestToken.sol";

contract DeploymentScript is Script {

    function setUp() public {}

    function run() public {
        string memory seedPhrase = vm.readFile(".secret");
        uint256 privateKey = vm.deriveKey(seedPhrase, 0);
        vm.startBroadcast(privateKey);
        Market market = Market(0x65874652c6FE3C29251F9817Fa8eDAAA6C3cA5fb);
        market.changeShareCreatorWhitelist(address(0xb146d65dfa8F5995dd1feBBeF0a37123c2c44fD8), true);
        vm.stopBroadcast();
    }
}
