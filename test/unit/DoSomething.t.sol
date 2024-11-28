// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest, Vm} from "../BaseTest.t.sol";
import {MockEverestConsumer} from "../mocks/MockEverestConsumer.sol";

/// @notice `doSomething()` is an example of a compliantly-restricted function
contract DoSomethingTest is BaseTest {
    function test_compliant_doSomething_success() public {
        /// @dev set the user to compliant
        _setUserToCompliant(user);

        (, bytes memory retDataBefore) = address(compliantProxy).call(abi.encodeWithSignature("getIncrementedValue()"));
        (uint256 incrementedValueBefore) = abi.decode(retDataBefore, (uint256));
        assertEq(incrementedValueBefore, 0);

        vm.recordLogs();

        vm.prank(user);
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("doSomething()"));
        require(success, "delegate call to doSomething() failed");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("CompliantCheckPassed()");
        bool eventEmitted;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                eventEmitted = true;
            }
        }
        assertTrue(eventEmitted);

        (, bytes memory retDataAfter) = address(compliantProxy).call(abi.encodeWithSignature("getIncrementedValue()"));
        (uint256 incrementedValueAfter) = abi.decode(retDataAfter, (uint256));
        assertEq(incrementedValueAfter, 1);
    }

    function test_compliant_doSomething_revertsWhen_userNotCompliant() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("Compliant__NonCompliantUser(address)", user));
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("doSomething()"));
    }

    function test_compliant_doSomething_revertsWhen_notProxy() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("Compliant__OnlyProxy()"));
        compliant.doSomething();
    }
}
