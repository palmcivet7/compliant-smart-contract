// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest, Vm, LinkTokenInterface} from "../BaseTest.t.sol";
import {MockLinkToken} from "../mocks/MockLinkToken.sol";

contract OnTokenTransferTest is BaseTest {
    function test_compliant_onTokenTransfer() public {
        bytes32 requestIdBefore = compliant.getLastEverestRequestId(user);
        assertEq(requestIdBefore, 0);

        uint256 amount = compliant.getFee();
        /// @dev requesting the kyc status of user
        /// @dev false because we are not performing automation
        bytes memory data = abi.encode(user, false);

        vm.recordLogs();

        vm.prank(user);
        LinkTokenInterface(link).transferAndCall(address(compliant), amount, data);

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

        bytes32 requestIdAfter = compliant.getLastEverestRequestId(user);
        bytes32 expectedRequestId = bytes32(uint256(uint160(user)));

        assertEq(requestIdAfter, expectedRequestId);
        assertEq(emittedRequestId, expectedRequestId);
        assertEq(user, emittedUser);
    }

    function test_compliant_onTokenTransfer_automation() public {
        bytes32 requestIdBefore = compliant.getLastEverestRequestId(user);
        assertEq(requestIdBefore, 0);

        uint256 amount = compliant.getAutomatedFee();
        /// @dev requesting the kyc status of user
        /// @dev true because we are performing automation
        bytes memory data = abi.encode(user, true);

        vm.recordLogs();

        vm.prank(user);
        LinkTokenInterface(link).transferAndCall(address(compliant), amount, data);

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

        bytes32 requestIdAfter = compliant.getLastEverestRequestId(user);
        bytes32 expectedRequestId = bytes32(uint256(uint160(user)));

        assertEq(requestIdAfter, expectedRequestId);
        assertEq(emittedRequestId, expectedRequestId);
        assertEq(user, emittedUser);
    }

    function test_compliant_onTokenTransfer_revertsWhen_notLink() public {
        vm.startPrank(user);
        MockLinkToken erc677 = new MockLinkToken();
        erc677.initializeMockLinkToken();

        uint256 amount = compliant.getFee();
        bytes memory data = abi.encode(user, false);

        vm.expectRevert(abi.encodeWithSignature("Compliant__OnlyLinkToken()"));
        erc677.transferAndCall(address(compliant), amount, data);
        vm.stopPrank();
    }

    function test_compliant_onTokenTransfer_revertsWhen_insufficientAmount() public {
        vm.startPrank(user);
        uint256 fee = compliant.getFee();
        uint256 amount = fee - 1;
        bytes memory data = abi.encode(user, false);

        vm.expectRevert(
            abi.encodeWithSignature("Compliant__InsufficientLinkTransferAmount(uint256,uint256)", amount, fee)
        );
        LinkTokenInterface(link).transferAndCall(address(compliant), amount, data);
        vm.stopPrank();
    }
}
