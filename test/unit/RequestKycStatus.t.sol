// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest, Vm, LinkTokenInterface} from "./BaseTest.t.sol";

contract RequestKycStatusTest is BaseTest {
    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public override {
        BaseTest.setUp();

        uint256 approvalAmount = compliant.getAutomatedFee() + compliant.getFee();

        vm.prank(user);
        LinkTokenInterface(link).approve(address(compliant), approvalAmount);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/
    function test_compliant_requestKycStatus() public {
        bytes32 requestIdBefore = compliant.getLastEverestRequestId(user);
        assertEq(requestIdBefore, 0);

        uint256 linkBalanceBefore = LinkTokenInterface(link).balanceOf(user);

        vm.recordLogs();

        vm.prank(user);
        uint256 fee = compliant.requestKycStatus(user, false); // false for no automation

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

        bytes32 requestIdAfter = compliant.getLastEverestRequestId(user);
        bytes32 expectedRequestId = bytes32(uint256(uint160(user)));

        assertEq(linkBalanceAfter + compliant.getFee(), linkBalanceBefore);
        assertEq(requestIdAfter, expectedRequestId);
        assertEq(emittedRequestId, expectedRequestId);
        assertEq(user, emittedUser);
        assertEq(fee, compliant.getFee());
    }

    function test_compliant_requestKycStatus_automated() public {
        bytes32 requestIdBefore = compliant.getLastEverestRequestId(user);
        assertEq(requestIdBefore, 0);

        uint256 linkBalanceBefore = LinkTokenInterface(link).balanceOf(user);

        vm.recordLogs();

        vm.prank(user);
        uint256 fee = compliant.requestKycStatus(user, true); // true for automation

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

        bytes32 requestIdAfter = compliant.getLastEverestRequestId(user);
        bytes32 expectedRequestId = bytes32(uint256(uint160(user)));

        assertEq(linkBalanceAfter + compliant.getAutomatedFee(), linkBalanceBefore);
        assertEq(requestIdAfter, expectedRequestId);
        assertEq(emittedRequestId, expectedRequestId);
        assertEq(user, emittedUser);
        assertEq(fee, compliant.getAutomatedFee());
    }
}
