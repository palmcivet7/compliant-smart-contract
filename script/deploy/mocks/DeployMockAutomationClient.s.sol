// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";
import {MockAutomationClient} from "../../../test/mocks/MockAutomationClient.sol";

contract DeployMockAutomationClient is Script {
    function run() external returns (MockAutomationClient) {
        vm.startBroadcast();
        MockAutomationClient mockAutomationClient = new MockAutomationClient();
        vm.stopBroadcast();

        return (mockAutomationClient);
    }
}
