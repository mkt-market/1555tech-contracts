// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "forge-std/Script.sol";
import "../src/Market.sol";
import "../src/test/TestToken.sol";

contract DeploymentScript is Script {
    // https://docs.canto.io/evm-development/contract-addresses
    address linearBondingCurve = address(0xD5aCAEccffD7F3A400098474fA7895A0CF36688d);

    function setUp() public {}

    function run() public {
        string memory seedPhrase = vm.readFile(".secret");
        uint256 privateKey = vm.deriveKey(seedPhrase, 0);
        vm.startBroadcast(privateKey);
        Market market = Market(0x13005cae12f10b854Ec06397C04CF92512Bf2484);
        market.createNewShare("test", linearBondingCurve, "https://someurl.com");
        vm.stopBroadcast();
    }
}
