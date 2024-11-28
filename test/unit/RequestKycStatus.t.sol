// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest, Vm, LinkTokenInterface, Compliant} from "../BaseTest.t.sol";

contract RequestKycStatusTest is BaseTest {
    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public override {
        BaseTest.setUp();

        uint256 approvalAmount = compliant.getFeeWithAutomation() + compliant.getFee();

        vm.prank(user);
        LinkTokenInterface(link).approve(address(compliant), approvalAmount);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/
    function test_compliant_requestKycStatus_success() public {
        uint256 linkBalanceBefore = LinkTokenInterface(link).balanceOf(user);

        vm.recordLogs();

        vm.prank(user);
        uint256 fee = compliant.requestKycStatus(user, false, ""); // false for no automation

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("KYCStatusRequested(bytes32,address)");
        bytes32 emittedRequestId;
        address emittedUser;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                emittedRequestId = logs[i].topics[1];
                emittedUser = address(uint160(uint256(logs[i].topics[2])));
            }
        }

        uint256 linkBalanceAfter = LinkTokenInterface(link).balanceOf(user);
        bytes32 expectedRequestId = bytes32(uint256(uint160(user)));

        assertEq(linkBalanceAfter + compliant.getFee(), linkBalanceBefore);
        assertEq(emittedRequestId, expectedRequestId);
        assertEq(user, emittedUser);
        assertEq(fee, compliant.getFee());
    }

    function test_compliant_requestKycStatus_automation() public {
        uint256 linkBalanceBefore = LinkTokenInterface(link).balanceOf(user);

        vm.recordLogs();

        bytes memory compliantCalldata = abi.encode(1);

        vm.prank(user);
        // could change "" for some dummy data to assert correct data is stored
        uint256 fee = compliant.requestKycStatus(user, true, compliantCalldata); // true for automation

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("KYCStatusRequested(bytes32,address)");
        bytes32 emittedRequestId;
        address emittedUser;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                emittedRequestId = logs[i].topics[1];
                emittedUser = address(uint160(uint256(logs[i].topics[2])));
            }
        }

        uint256 linkBalanceAfter = LinkTokenInterface(link).balanceOf(user);

        bytes32 expectedRequestId = bytes32(uint256(uint160(user)));

        Compliant.PendingRequest memory pendingRequest = compliant.getPendingRequest(user);
        bool isPending = pendingRequest.isPending;
        bytes memory storedCalldata = pendingRequest.compliantCalldata;

        assertTrue(isPending);
        assertEq(storedCalldata, compliantCalldata);
        assertEq(linkBalanceAfter + compliant.getFeeWithAutomation(), linkBalanceBefore);
        assertEq(emittedRequestId, expectedRequestId);
        assertEq(user, emittedUser);
        assertEq(fee, compliant.getFeeWithAutomation());
    }

    function test_compliant_requestKycStatus_revertsWhen_userPendingRequest() public {
        uint256 approvalAmount = compliant.getFeeWithAutomation() * 2;
        vm.startPrank(user);
        LinkTokenInterface(link).approve(address(compliant), approvalAmount);
        compliant.requestKycStatus(user, true, ""); // true for automation
        vm.expectRevert(abi.encodeWithSignature("Compliant__PendingRequestExists(address)", user));
        compliant.requestKycStatus(user, true, ""); // true for automation
        vm.stopPrank();
    }

    function test_compliant_requestKycStatus_revertsWhen_notProxy() public {
        uint256 approvalAmount = compliant.getFeeWithAutomation() * 2;
        vm.startPrank(user);
        LinkTokenInterface(link).approve(address(compliant), approvalAmount);
        vm.expectRevert(abi.encodeWithSignature("Compliant__OnlyProxy()"));
        compliant.requestKycStatus(user, true, ""); // true for automation
    }
}
