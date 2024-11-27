// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {IAutomationRegistryMaster} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/v2_2/IAutomationRegistryMaster.sol";

contract ConstructorTest is BaseTest {
    function test_compliant_constructor() public view {
        assertEq(address(compliant.getEverest()), everest);
        assertEq(address(compliant.getLink()), link);
        assertEq(address(compliant.getPriceFeed()), linkUsdFeed);
        assertEq(address(compliant.getAutomation()), automation);
        assertEq(compliant.getForwarder(), IAutomationRegistryMaster(automation).getForwarder(compliant.getUpkeepId()));
        assertGt(compliant.getUpkeepId(), 0);

        assertEq(compliant.owner(), deployer);
    }
}
