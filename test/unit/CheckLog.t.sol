// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest, LinkTokenInterface, Compliant} from "../BaseTest.t.sol";
import {ILogAutomation, Log} from "@chainlink/contracts/src/v0.8/automation/interfaces/ILogAutomation.sol";
import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";

contract CheckLogTest is BaseTest {
    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/
    /// @notice this test should be commented out if the cannotExecute modifier is removed from checkLog
    function test_compliant_checkLog_revertsWhen_called() public {
        Log memory log = _createLog(true, address(compliant));
        vm.expectRevert(abi.encodeWithSignature("OnlySimulatedBackend()"));
        compliant.checkLog(log, "");
    }

    // /// @notice this test will fail unless the cannotExecute modifier is removed from checkLog
    // function test_compliant_checkLog_isCompliant_and_pending() public {
    //     /// @dev set user to pending request
    //     bytes memory emptyCallData = "";
    //     _setUserPendingRequest(emptyCallData);

    //     /// @dev check log
    //     Log memory log = _createLog(true, address(compliant));
    //     (bool upkeepNeeded, bytes memory performData) = compliant.checkLog(log, "");

    //     /// @dev decode performData
    //     (bytes32 encodedRequestId, address encodedUser, bool isCompliant) =
    //         abi.decode(performData, (bytes32, address, bool));

    //     bytes32 expectedRequestId = bytes32(uint256(uint160(user)));
    //     assertEq(expectedRequestId, encodedRequestId);
    //     assertEq(user, encodedUser);
    //     assertTrue(isCompliant);
    //     assertTrue(upkeepNeeded);
    // }

    // /// @notice this test will fail unless the cannotExecute modifier is removed from checkLog
    // function test_compliant_checkLog_isNonCompliant_and_pending() public {
    //     /// @dev set user to pending request
    //     bytes memory emptyCallData = "";
    //     _setUserPendingRequest(emptyCallData);

    //     /// @dev check log
    //     Log memory log = _createLog(false, address(compliant));
    //     (bool upkeepNeeded, bytes memory performData) = compliant.checkLog(log, "");

    //     /// @dev decode performData
    //     (bytes32 encodedRequestId, address encodedUser, bool isCompliant) =
    //         abi.decode(performData, (bytes32, address, bool));

    //     bytes32 expectedRequestId = bytes32(uint256(uint160(user)));
    //     assertEq(expectedRequestId, encodedRequestId);
    //     assertEq(user, encodedUser);
    //     assertFalse(isCompliant);
    //     assertTrue(upkeepNeeded);
    // }

    // /// @notice this test will fail unless the cannotExecute modifier is removed from checkLog
    // function test_compliant_checkLog_isCompliant_and_notPending() public view {
    //     /// @dev check log
    //     Log memory log = _createLog(true, address(compliant));
    //     (bool upkeepNeeded, bytes memory performData) = compliant.checkLog(log, "");

    //     assertEq(performData, "");
    //     assertFalse(upkeepNeeded);
    // }

    // /// @notice this test will fail unless the cannotExecute modifier is removed from checkLog
    // function test_compliant_checkLog_revertsWhen_request_notCurrentContract() public {
    //     address revealer = makeAddr("revealer");

    //     /// @dev check log
    //     Log memory log = _createLog(true, revealer);
    //     vm.expectRevert(abi.encodeWithSignature("Compliant__RequestNotMadeByThisContract()"));
    //     compliant.checkLog(log, "");
    // }

    /*//////////////////////////////////////////////////////////////
                                UTILITY
    //////////////////////////////////////////////////////////////*/
    function _createLog(bool isCompliant, address revealer) internal view returns (Log memory) {
        bytes32[] memory topics = new bytes32[](3);
        bytes32 eventSignature = keccak256("Fulfilled(bytes32,address,address,uint8,uint40)");
        bytes32 requestId = bytes32(uint256(uint160(user)));
        bytes32 addressToBytes32 = bytes32(uint256(uint160(revealer)));
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
}
