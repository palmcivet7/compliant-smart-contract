// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest, Vm} from "./BaseTest.t.sol";
import {MockAutomationConsumer} from "../mocks/MockAutomationConsumer.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

contract RequestKycStatusTest is BaseTest {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint96 constant AUTOMATION_MIN_BALANCE = 1e17;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public override {
        BaseTest.setUp();

        vm.startPrank(deployer);
        MockAutomationConsumer(automation).setMinBalance(AUTOMATION_MIN_BALANCE);
        LinkTokenInterface(link).approve(address(compliant), compliant.getFee());
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/
    function test_compliant_requestKycStatus() public {
        bytes32 requestIdBefore = compliant.getLastEverestRequestId(user);
        assertEq(requestIdBefore, 0);

        uint256 linkBalanceBefore = LinkTokenInterface(link).balanceOf(deployer);

        vm.recordLogs();

        vm.prank(deployer);
        compliant.requestKycStatus(user);

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

        uint256 linkBalanceAfter = LinkTokenInterface(link).balanceOf(deployer);

        bytes32 requestIdAfter = compliant.getLastEverestRequestId(user);
        bytes32 expectedRequestId = bytes32(uint256(uint160(user)));

        assertEq(linkBalanceAfter + compliant.getFee(), linkBalanceBefore);
        assertEq(requestIdAfter, expectedRequestId);
        assertEq(emittedRequestId, expectedRequestId);
        assertEq(user, emittedUser);
    }
}
