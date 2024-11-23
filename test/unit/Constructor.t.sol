// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest} from "./BaseTest.t.sol";

contract ConstructorTest is BaseTest {
    function test_compliant_constructor() public view {
        assertEq(address(compliant.getEverest()), everest);
        assertEq(address(compliant.getLink()), link);
        assertEq(address(compliant.getPriceFeed()), priceFeed);
        assertEq(address(compliant.getAutomation()), automation);
        assertEq(compliant.getForwarder(), forwarder);
        assertEq(compliant.getClaSubId(), claSubId);

        assertEq(compliant.owner(), deployer);
    }
}
