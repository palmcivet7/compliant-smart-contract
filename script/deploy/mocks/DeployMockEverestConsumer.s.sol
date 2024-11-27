// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";
import {MockEverestConsumer} from "../../../test/mocks/MockEverestConsumer.sol";

contract DeployMockEverestConsumer is Script {
    function run() external returns (MockEverestConsumer) {
        vm.startBroadcast();
        HelperConfig config = new HelperConfig();
        (, address link,,,,,) = config.activeNetworkConfig();
        MockEverestConsumer mockEverest = new MockEverestConsumer(link);
        vm.stopBroadcast();

        return (mockEverest);
    }
}
