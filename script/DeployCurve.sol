// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "forge-std/Script.sol";
import "../src/bonding_curve/LinearBondingCurve.sol";
import "../src/Market.sol";
import "../src/test/TestToken.sol";

contract DeploymentScript is Script {
    // https://docs.canto.io/evm-development/contract-addresses
    uint256 constant LINEAR_BONDING_CURVE_INCREASE = 1e18;
    address offchainSigner = address(0x29D4B2B80A8de138d8dfDF415666501d0278AEdD);

    function setUp() public {}

    function run() public {
        string memory seedPhrase = vm.readFile(".secret");
        uint256 privateKey = vm.deriveKey(seedPhrase, 0);
        vm.startBroadcast(privateKey);
        LinearBondingCurve bondingCurve = new LinearBondingCurve(LINEAR_BONDING_CURVE_INCREASE);
        Market market = Market(0x5525ac3D13064CC7615d04d9cB2a4C6274cd9E07);
        market.changeBondingCurveAllowed(address(bondingCurve), true);
        vm.stopBroadcast();
    }
}
