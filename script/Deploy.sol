// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "forge-std/Script.sol";
import "../src/Market.sol";
// import "../src/Contract.sol";

contract DeploymentScript is Script {
    // https://docs.canto.io/evm-development/contract-addresses
    address constant NOTE = address(0x4e71A2E537B7f9D9413D3991D37958c0b5e1e503);
    uint256 constant LINEAR_BONDING_CURVE_INCREASE = 1e18;
    address offchainSigner = address(0x29D4B2B80A8de138d8dfDF415666501d0278AEdD);
    address newOwner = address(0x5c2aeB0F2b70E3896d5cde7Ed02e78961E53FA2c);

    function setUp() public {}

    function run() public {
        // string memory seedPhrase = vm.readFile(".secret");
        // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
        // vm.startBroadcast(privateKey);
        // LinearBondingCurve bondingCurve = LinearBondingCurve(address(0x03BCE3eDEaD608171FBcDaB63961dbba3e811e45));
        // Market market = new Market(NOTE, offchainSigner);
        // market.changeBondingCurveAllowed(address(bondingCurve), true);
        // market.transferOwnership(newOwner);
        // vm.stopBroadcast();
    }
}
