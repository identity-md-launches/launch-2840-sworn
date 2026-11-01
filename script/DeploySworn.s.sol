// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {SwornToken} from "../src/SwornToken.sol";

/// @notice Reference deployment for local review only. The production launch is performed by IMD's
/// factory from the attested bytecode; this script reads no environment and takes no arguments.
contract DeploySworn is Script {
    function deploy() public returns (SwornToken token) {
        token = new SwornToken();
    }

    function run() external returns (SwornToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
