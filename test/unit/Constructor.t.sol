// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest} from "../BaseTest.t.sol";

contract ConstructorTest is BaseTest {
    function test_compliant_constructor() public view {
        assertEq(address(compliant.getEverest()), address(everest));
        assertEq(address(compliant.getLink()), link);
        assertEq(address(compliant.getLinkUsdFeed()), linkUsdFeed);
        assertEq(address(compliant.getForwarder()), address(forwarder));
        assertEq(compliant.getUpkeepId(), upkeepId);
    }
}
