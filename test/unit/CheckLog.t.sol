// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest, LinkTokenInterface} from "../BaseTest.t.sol";
import {ILogAutomation, Log} from "@chainlink/contracts/src/v0.8/automation/interfaces/ILogAutomation.sol";
import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";

contract CheckLogTest is BaseTest {
    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/
    function test_compliant_checkLog_revertsWhen_called() public {
        Log memory log = _createLog(true);
        vm.expectRevert(abi.encodeWithSignature("OnlySimulatedBackend()"));
        compliant.checkLog(log, "");
    }

    /// @notice this test will fail unless the cannotExecute modifier is removed from checkLog
    function test_compliant_checkLog_isCompliant_and_pending() public {
        /// @dev set user to pending request
        _setUserPendingRequest();

        /// @dev check log
        Log memory log = _createLog(true);
        (bool upkeepNeeded, bytes memory performData) = compliant.checkLog(log, "");

        /// @dev decode performData
        (bytes32 encodedRequestId, address encodedUser, bool isCompliant) =
            abi.decode(performData, (bytes32, address, bool));

        bytes32 expectedRequestId = bytes32(uint256(uint160(user)));
        assertEq(expectedRequestId, encodedRequestId);
        assertEq(user, encodedUser);
        assertTrue(isCompliant);
        assertTrue(upkeepNeeded);
    }

    /// @notice this test will fail unless the cannotExecute modifier is removed from checkLog
    function test_compliant_checkLog_isNonCompliant_and_pending() public {
        /// @dev set user to pending request
        _setUserPendingRequest();

        /// @dev check log
        Log memory log = _createLog(false);
        (bool upkeepNeeded, bytes memory performData) = compliant.checkLog(log, "");

        /// @dev decode performData
        (bytes32 encodedRequestId, address encodedUser, bool isCompliant) =
            abi.decode(performData, (bytes32, address, bool));

        bytes32 expectedRequestId = bytes32(uint256(uint160(user)));
        assertEq(expectedRequestId, encodedRequestId);
        assertEq(user, encodedUser);
        assertFalse(isCompliant);
        assertTrue(upkeepNeeded);
    }

    /// @notice this test will fail unless the cannotExecute modifier is removed from checkLog
    function test_compliant_checkLog_isCompliant_and_notPending() public view {
        /// @dev check log
        Log memory log = _createLog(true);
        (bool upkeepNeeded, bytes memory performData) = compliant.checkLog(log, "");

        assertEq(performData, "");
        assertFalse(upkeepNeeded);
    }

    /*//////////////////////////////////////////////////////////////
                                UTILITY
    //////////////////////////////////////////////////////////////*/
    function _createLog(bool isCompliant) internal view returns (Log memory) {
        bytes32[] memory topics = new bytes32[](3);
        bytes32 eventSignature = keccak256("Fulfilled(bytes32,address,address,uint8,uint40)");
        bytes32 requestId = bytes32(uint256(uint160(user)));
        bytes32 addressToBytes32 = bytes32(uint256(uint160(address(compliant)))); // revealer
        topics[0] = eventSignature;
        topics[1] = requestId;
        topics[2] = addressToBytes32;

        IEverestConsumer.Status status;

        if (isCompliant) status = IEverestConsumer.Status.KYCUser;
        else status = IEverestConsumer.Status.NotFound;

        bytes memory data = abi.encode(user, status, block.timestamp);

        Log memory log = Log({
            index: 0,
            timestamp: block.timestamp,
            txHash: bytes32(0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef),
            blockNumber: block.number,
            blockHash: bytes32(0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890),
            source: address(everest),
            topics: topics,
            data: data
        });

        return log;
    }

    function _setUserPendingRequest() internal {
        uint256 amount = compliant.getFeeWithAutomation();
        bytes memory data = abi.encode(user, true);
        vm.prank(user);
        LinkTokenInterface(link).transferAndCall(address(compliant), amount, data);

        bool isPending = compliant.getPendingRequest(user);
        assertTrue(isPending);
    }
}
