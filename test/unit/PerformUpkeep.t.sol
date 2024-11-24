// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest, Vm, Compliant} from "../BaseTest.t.sol";

contract PerformUpkeepTest is BaseTest {
    function test_compliant_performUpkeep_isCompliant() public {
        uint256 incrementedValueBefore = compliant.getAutomatedIncrement();
        assertEq(incrementedValueBefore, 0);

        bytes32 requestId = bytes32(uint256(uint160(user)));
        bytes memory performData = abi.encode(requestId, user, true);

        vm.recordLogs();
        vm.prank(forwarder);
        compliant.performUpkeep(performData);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 fulfilledEventSignature = keccak256("KYCStatusRequestFulfilled(bytes32,address,bool)");
        bytes32 emittedRequestId;
        address emittedUser;
        bool emittedBool;
        bytes32 compliantEventSignature = keccak256("CompliantCheckPassed()");
        bool compliantEventEmitted;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == fulfilledEventSignature) {
                emittedRequestId = logs[i].topics[1];
                emittedUser = address(uint160(uint256(logs[i].topics[2])));
                emittedBool = (logs[i].topics[3] != bytes32(0));
            }

            if (logs[i].topics[0] == compliantEventSignature) {
                compliantEventEmitted = true;
            }
        }

        assertEq(requestId, emittedRequestId);
        assertEq(user, emittedUser);
        assertTrue(emittedBool);
        assertTrue(compliantEventEmitted);

        uint256 incrementedValueAfter = compliant.getAutomatedIncrement();
        assertEq(incrementedValueAfter, 1);

        Compliant.PendingRequest memory request = compliant.getPendingRequest(user);
        assertFalse(request.isPending);
    }

    function test_compliant_performUpkeep_isNonCompliant() public {
        uint256 incrementedValueBefore = compliant.getAutomatedIncrement();
        assertEq(incrementedValueBefore, 0);

        bytes32 requestId = bytes32(uint256(uint160(user)));
        bytes memory performData = abi.encode(requestId, user, false);

        vm.recordLogs();
        vm.prank(forwarder);
        compliant.performUpkeep(performData);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 fulfilledEventSignature = keccak256("KYCStatusRequestFulfilled(bytes32,address,bool)");
        bytes32 emittedRequestId;
        address emittedUser;
        bool emittedBool;
        bytes32 compliantEventSignature = keccak256("CompliantCheckPassed()");
        bool compliantEventEmitted;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == fulfilledEventSignature) {
                emittedRequestId = logs[i].topics[1];
                emittedUser = address(uint160(uint256(logs[i].topics[2])));
                emittedBool = (logs[i].topics[3] != bytes32(0));
            }

            if (logs[i].topics[0] == compliantEventSignature) {
                compliantEventEmitted = true;
            }
        }

        assertEq(requestId, emittedRequestId);
        assertEq(user, emittedUser);
        assertFalse(emittedBool);
        assertFalse(compliantEventEmitted);

        uint256 incrementedValueAfter = compliant.getAutomatedIncrement();
        assertEq(incrementedValueAfter, 0);

        Compliant.PendingRequest memory request = compliant.getPendingRequest(user);
        assertFalse(request.isPending);
    }

    function test_compliant_performUpkeep_revertsWhen_not_forwarder() public {
        vm.expectRevert(abi.encodeWithSignature("Compliant__OnlyForwarder()"));
        compliant.performUpkeep("");
    }
}
