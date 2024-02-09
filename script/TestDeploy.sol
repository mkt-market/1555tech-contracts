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
        TestToken token = TestToken(0xA0E000057430d08269C882940aDC8842DED37eb3);
        LinearBondingCurve bondingCurve = LinearBondingCurve(0xDEdAB9560614a79B44e4c2b480209C55D5e1d0D0);
        Market market = new Market(address(token), offchainSigner); // TODO: Define signer
        market.changeBondingCurveAllowed(address(bondingCurve), true);
        market.transferOwnership(address(0x29D4B2B80A8de138d8dfDF415666501d0278AEdD));
        vm.stopBroadcast();
    }
}
