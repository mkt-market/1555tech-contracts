// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "forge-std/Script.sol";
import "../src/Market.sol";
import "../src/test/TestToken.sol";

contract DeploymentScript is Script {
    // https://docs.canto.io/evm-development/contract-addresses
    address linearBondingCurve = address(0x12e2ad2e58fA72fDDefa0F115DF2a42052529650);

    function setUp() public {}

    function run() public {
        string memory seedPhrase = vm.readFile(".secret");
        uint256 privateKey = vm.deriveKey(seedPhrase, 0);
        vm.startBroadcast(privateKey);
        Market market = Market(0xFDcB59757Dad7FaB54778C6e964923A77Cbd49e6);
        market.changeOffchainSigner(address(0x29D4B2B80A8de138d8dfDF415666501d0278AEdD));
        vm.stopBroadcast();
    }
}
