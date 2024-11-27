// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {Compliant} from "../../src/Compliant.sol";

contract DeployCompliant is Script {
    function run() external returns (Compliant) {
        vm.startBroadcast();
        HelperConfig config = new HelperConfig();
        (
            address everest,
            address link,
            address priceFeed,
            address automation,
            address registrar,
            address swapRouter,
            address linkEthFeed
        ) = config.activeNetworkConfig();
        Compliant mockEverest = new Compliant(everest, link, priceFeed, automation, registrar, swapRouter, linkEthFeed);
        vm.stopBroadcast();

        return (mockEverest);
    }
}
