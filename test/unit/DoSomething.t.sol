// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest, Vm} from "../BaseTest.t.sol";
import {MockEverestConsumer} from "../mocks/MockEverestConsumer.sol";

/// @notice `doSomething()` is an example of a compliantly-restricted function
contract DoSomethingTest is BaseTest {
    function test_compliant_doSomething() public {
        /// @dev set the user to compliant
        _setUserToCompliant(user);

        uint256 incrementedValueBefore = compliant.getIncrementedValue();
        assertEq(incrementedValueBefore, 0);

        vm.recordLogs();

        vm.prank(user);
        compliant.doSomething();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("CompliantCheckPassed()");
        bool eventEmitted;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                eventEmitted = true;
            }
        }
        assertTrue(eventEmitted);

        uint256 incrementedValueAfter = compliant.getIncrementedValue();
        assertEq(incrementedValueAfter, 1);
    }

    function test_compliant_doSomething_revertsWhen_userNotCompliant() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("Compliant__NonCompliantUser(address)", user));
        compliant.doSomething();
    }
}
