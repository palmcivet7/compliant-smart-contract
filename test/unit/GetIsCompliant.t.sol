// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {MockEverestConsumer} from "../mocks/MockEverestConsumer.sol";

contract GetIsCompliantTest is BaseTest {
    function test_compliant_getIsCompliant() public {
        _setUserToCompliant(user);
        bool isCompliant = compliant.getIsCompliant(user);
        assertTrue(isCompliant);
    }
}
