// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "forge-std/Script.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "../src/Contract.sol";

contract TransferForTesting is Script {
    // https://docs.canto.io/evm-development/contract-addresses
    // address constant NOTE = address(0x4e71A2E537B7f9D9413D3991D37958c0b5e1e503);
    address constant NOTE = address(0x03F734Bd9847575fDbE9bEaDDf9C166F880B5E5f);

    function setUp() public {}

    function run() public {
        string memory seedPhrase = vm.readFile(".secret");
        uint256 privateKey = vm.deriveKey(seedPhrase, 0);
        vm.startBroadcast(privateKey);
        SafeERC20.safeTransfer(IERC20(NOTE), address(0xEfC711B22F4fDbCBC221aC7c116e90c699D0b708), 1000 * 1e18);
        vm.stopBroadcast();
    }
}
