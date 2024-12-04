// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {console2} from "forge-std/Test.sol";
import {Handler} from "./Handler.t.sol";
import {Compliant} from "../../src/Compliant.sol";
import {
    BaseTest,
    Vm,
    LinkTokenInterface,
    HelperConfig,
    InitialImplementation,
    MockEverestConsumer,
    CompliantProxy,
    ProxyAdmin,
    ITransparentUpgradeableProxy,
    MockAutomationRegistry
} from "../BaseTest.t.sol";
import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";
import {IAutomationRegistryConsumer} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/IAutomationRegistryConsumer.sol";

contract Invariant is StdInvariant, BaseTest {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @dev initial value returned by registry.getMinBalance()
    uint96 internal constant AUTOMATION_MIN_BALANCE = 1e17;

    /// @dev contract handling calls to Compliant
    Handler internal handler;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public override {
        /// @dev get Mock deployments for local testing from config
        HelperConfig config = new HelperConfig();
        address everestAddress;
        (everestAddress, link, linkUsdFeed, registry,, forwarder) = config.activeNetworkConfig();
        everest = MockEverestConsumer(everestAddress);

        /// @dev deploy InitialImplementation
        InitialImplementation initialImplementation = new InitialImplementation();

        /// @dev record logs to get proxyAdmin contract address
        vm.recordLogs();

        /// @dev deploy CompliantProxy
        compliantProxy = new CompliantProxy(address(initialImplementation), proxyDeployer);

        /// @dev get proxyAdmin contract address from logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("AdminChanged(address,address)");
        address proxyAdmin;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                (, proxyAdmin) = abi.decode(logs[i].data, (address, address));
            }
        }

        /// @dev register automation
        upkeepId = 1;

        /// @dev deploy Compliant
        vm.prank(deployer);
        compliant = new Compliant(address(everest), link, linkUsdFeed, forwarder, upkeepId, address(compliantProxy));

        /// @dev upgradeToAndCall - set Compliant to new implementation and initialize deployer to owner
        bytes memory initializeData = abi.encodeWithSignature("initialize(address)", deployer);
        vm.prank(proxyDeployer);
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(compliantProxy)), address(compliant), initializeData
        );

        /// @dev set CompliantProxyAdmin to address(0) - making its last upgrade final and immutable
        vm.prank(proxyDeployer);
        ProxyAdmin(proxyAdmin).renounceOwnership();
        assertEq(ProxyAdmin(proxyAdmin).owner(), address(0));

        /// @dev assign owner
        (, bytes memory ownerData) = address(compliantProxy).call(abi.encodeWithSignature("owner()"));
        owner = abi.decode(ownerData, (address));

        /// @dev set automation min balance
        MockAutomationRegistry(registry).setMinBalance(AUTOMATION_MIN_BALANCE);

        //-----------------------------------------------------------------------------------------------

        /// @dev deploy handler
        handler = new Handler(
            compliant,
            address(compliantProxy),
            deployer,
            link,
            forwarder,
            address(everest),
            address(proxyAdmin),
            registry
        );

        /// @dev define appropriate function selectors
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = Handler.sendRequest.selector;
        // selectors[0] = Handler.onTokenTransfer.selector;
        // selectors[1] = Handler.requestKycStatus.selector;
        selectors[1] = Handler.doSomething.selector;
        selectors[2] = Handler.withdrawFees.selector;
        selectors[3] = Handler.externalImplementationCalls.selector;
        selectors[4] = Handler.changeFeeVariables.selector;

        /// @dev target handler and appropriate function selectors
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));

        excludeSender(address(proxyAdmin));
    }

    /*//////////////////////////////////////////////////////////////
                               INVARIANTS
    //////////////////////////////////////////////////////////////*/
    // 1. Proxy Protection:
    /// @dev no direct calls (that change state) to the proxy should succeed
    function invariant_onlyProxy_noDirectCallsSucceed() public view {
        assertEq(
            handler.g_directCallSuccesses(),
            0,
            "Invariant violated: Direct calls to implementation contract should never succeed."
        );
    }

    /// @dev all direct calls (that change state) to the proxy should revert
    function invariant_onlyProxy_directCallsRevert() public view {
        assertEq(
            handler.g_directImplementationCalls(),
            handler.g_directCallReverts(),
            "Invariant violated: All direct calls to implementation contract should revert."
        );
    }

    // 2. Pending Request Management:
    //  For any user address, at most one pending request can exist at a time (s_pendingRequests[user].isPending).
    //  If a pending request is fulfilled, isPending must be set to false.
    function invariant_pendingRequest() public {
        handler.forEachUser(this.checkPendingRequestForUser);
    }

    function checkPendingRequestForUser(address user) external {
        (, bytes memory retData) =
            address(compliantProxy).call(abi.encodeWithSignature("getPendingRequest(address)", user));
        Compliant.PendingRequest memory request = abi.decode(retData, (Compliant.PendingRequest));

        assertEq(
            request.isPending,
            handler.g_pendingRequests(user),
            "Invariant violated: Pending request should only be true whilst waiting for Chainlink Automation to be fulfilled."
        );
    }

    // 3. Fees Accounting:
    /// @dev fees available for owner to withdraw should always equal cumulative LINK earned minus any already withdrawn
    function invariant_feesAccounting() public {
        (, bytes memory retData) = address(compliantProxy).call(abi.encodeWithSignature("getCompliantFeesToWithdraw()"));
        uint256 fees = abi.decode(retData, (uint256));

        assertEq(
            fees,
            handler.g_totalFeesEarned() - handler.g_totalFeesWithdrawn(),
            "Invariant violated: Compliant Protocol fees available to withdraw should be total earned minus total withdrawn."
        );
    }

    // 4. KYC Status Consistency:
    /// @dev A user marked as compliant (_isCompliant(user)) must have their latest fulfilled KYC request isKYCUser = true.
    function invariant_compliantStatusIntegrity() public {
        handler.forEachUser(this.checkCompliantStatusForUser);
    }

    function checkCompliantStatusForUser(address user) external {
        (, bytes memory retData) =
            address(compliantProxy).call(abi.encodeWithSignature("getIsCompliant(address)", user));
        bool isCompliant = abi.decode(retData, (bool));

        IEverestConsumer.Request memory request = IEverestConsumer(address(everest)).getLatestFulfilledRequest(user);

        assertEq(
            isCompliant,
            request.isKYCUser,
            "Invariant violated: Compliant status returned by contract should be the same as latest fulfilled Everest request."
        );
    }

    // 5. Fee Calculation:
    /// @dev the fee for KYC requests should always be the sum of _calculateCompliantFee() + i_everest.oraclePayment().
    function invariant_feeCalculation_noAutomation() public {
        (, bytes memory retData) = address(compliantProxy).call(abi.encodeWithSignature("getFee()"));
        uint256 fee = abi.decode(retData, (uint256));

        uint256 oraclePayment = IEverestConsumer(address(everest)).oraclePayment();
        uint256 expectedFee = oraclePayment + compliant.getCompliantFee();

        assertEq(
            fee,
            expectedFee,
            "Invariant violated: Fee for a standard request should always be equal to Compliant and Everest fee."
        );
    }

    /// @dev the fee for automated requests should always be the sum of compliantFee, everestFee and upkeep minBalance.
    function invariant_feeCalculation_withAutomation() public {
        (, bytes memory retData) = address(compliantProxy).call(abi.encodeWithSignature("getFeeWithAutomation()"));
        uint256 fee = abi.decode(retData, (uint256));

        uint256 oraclePayment = IEverestConsumer(address(everest)).oraclePayment();
        uint256 minBalance = IAutomationRegistryConsumer(registry).getMinBalance(upkeepId);
        uint256 expectedFee = oraclePayment + minBalance + compliant.getCompliantFee();

        assertEq(
            fee,
            expectedFee,
            "Invariant violated: Fee for a request with Automation should always equal the Compliant, Everest, and upkeep minBalance."
        );
    }

    // 6. Compliance Logic:
    /// @dev only compliant users can call compliant restricted logic
    function invariant_compliantLogic_manualExecution() public {
        handler.forEachUser(this.checkDoSomethingLogic);
    }

    function checkDoSomethingLogic(address user) external {
        /// @dev fetch user's compliant status and manually call compliant restricted logic
        IEverestConsumer.Request memory request = IEverestConsumer(address(everest)).getLatestFulfilledRequest(user);
        vm.prank(user);
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("doSomething()"));

        /// @dev assert conditional invariant
        if (success) {
            assertTrue(
                request.isKYCUser,
                "Invariant violated: Only users who completed Everest KYC should be able to manually execute compliant logic."
            );
        } else {
            assertFalse(
                request.isKYCUser,
                "Invariant violated: Users who have not completed Everest KYC should not be able to execute compliant logic."
            );
        }
    }

    /// @dev assert manually executed compliant restricted logic changes state correctly
    function invariant_compliantLogic_stateChange_manualExecution() public {
        (, bytes memory retData) = address(compliantProxy).call(abi.encodeWithSignature("getIncrementedValue()"));
        uint256 incrementedValue = abi.decode(retData, (uint256));

        assertEq(
            incrementedValue,
            handler.g_manualIncrement(),
            "Invariant violated: Manually executed Compliant restricted logic state change should be consistent."
        );
    }

    /// @dev assert automated compliant restricted logic changes state correctly
    function invariant_compliantLogic_stateChange_withAutomation() public {
        (, bytes memory retData) = address(compliantProxy).call(abi.encodeWithSignature("getAutomatedIncrement()"));
        uint256 incrementedValue = abi.decode(retData, (uint256));

        assertEq(
            incrementedValue,
            handler.g_automationIncrement(),
            "Invariant violated: Automated Compliant restricted logic state change should be consistent."
        );
    }

    /// @dev check that CompliantCheckPassed() event is emitted everytime a fulfilled request isCompliant
    function invariant_compliantLogic_withAutomation_events() public view {
        assertEq(
            handler.g_fulfilledRequestIsCompliant(),
            handler.g_automatedCompliantCheckPassed(),
            "Invariant violated: If fulfilled request is compliant, automated Compliant restricted logic should be accessed."
        );
    }

    // 7. Upkeep Execution: NOTE: THIS WOULD REQUIRE LOCAL CHAINLINK AUTOMATION SIMULATOR
    //  performUpkeep should only process requests where checkLog indicates that upkeepNeeded is true.
    //  Automation-related requests (isAutomated = true) should add funds to the Chainlink registry via registry.addFunds.

    // 8. Forwarder Protection:
    /// @dev only the forwarder can call performUpkeep
    function invariant_onlyForwarder_canCall_performUpkeep() public {
        handler.forEachUser(this.checkForwarderCanCallPerformUpkeep);
    }

    function checkForwarderCanCallPerformUpkeep(address user) external {
        bytes32 requestId = bytes32(uint256(uint160(user)));
        bytes memory performData = abi.encode(requestId, user, true);

        // Case 1: Forwarder should succeed
        vm.prank(forwarder);
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("performUpkeep(bytes)", performData));
        assertTrue(success, "Invariant violated: Forwarder should be able to call performUpkeep");

        // Case 2: Non-forwarder should fail
        vm.assume(user != forwarder);
        vm.prank(user);
        (success,) = address(compliantProxy).call(abi.encodeWithSignature("performUpkeep(bytes)", performData));
        assertFalse(success, "Invariant violated: Non-forwarder should not be able to call performUpkeep");
    }

    // 9. Event Consistency:
    /// @dev assert KYCStatusRequested event is emitted for every request
    function invariant_eventConsistency_kycStatusRequested() public view {
        assertEq(
            handler.g_requestedEventsEmitted(),
            handler.g_requestsMade(),
            "Invariant violated: A KYCStatusRequested event should be emitted for every request."
        );
    }

    /// @dev every KYC status request emits a KYCStatusRequested event with the correct everestRequestId and user.
    function invariant_eventConsistency_kycStatusRequested_requestId() public {
        handler.forEachUser(this.checkKYCStatusRequestedEvent);
    }

    function checkKYCStatusRequestedEvent(address user) external view {
        bytes32 expectedRequestId = bytes32(uint256(uint160(user)));

        if (handler.g_requestedUsers(user)) {
            assertEq(
                expectedRequestId,
                handler.g_requestedEventRequestId(user),
                "Invariant violated: KYCStatusRequested event params should emit correct requestId and user."
            );
        } else {
            assertEq(
                handler.g_requestedEventRequestId(user),
                0,
                "Invariant violated: A user who hasn't been requested should not have been emitted."
            );
        }
    }

    /// @dev assert KYCStatusRequestFulfilled event emitted for fulfilled *AUTOMATED* requests
    function invariant_eventConsistency_kycStatusRequestFulfilled() public view {
        assertEq(
            handler.g_compliantFulfilledEventsEmitted(),
            handler.g_requestsFulfilled(),
            "Invariant violated: A KYCStatusFulfilled event should be emitted for every request fulfilled."
        );
    }

    /// @dev KYCStatusRequestFulfilled event should emit the correct isCompliant status
    function invariant_eventConsistency_kycStatusRequestFulfilled_isCompliant() public {
        handler.forEachUser(this.checkFulfilledRequestEventsCompliantStatus);
    }

    function checkFulfilledRequestEventsCompliantStatus(address user) external view {
        if (handler.g_compliantFulfilledEventIsCompliant(user) && handler.g_requestedAddressToStatus(user)) {
            assertTrue(
                handler.g_everestFulfilledEventIsCompliant(user),
                "Invariant violated: Compliant status should be the same in automated Compliant Fulfilled event as Everest Fulfilled."
            );
        }
    }

    /// @dev KYCStatusRequestFulfilled event should emit the correct requestId
    function invariant_eventConsistency_kycStatusRequestFulfilled_requestId() public {
        handler.forEachUser(this.checkFulfilledRequestEventsRequestId);
    }

    function checkFulfilledRequestEventsRequestId(address user) external view {
        if (handler.g_fulfilledUsers(user)) {
            assertEq(
                handler.g_everestFulfilledEventRequestId(user),
                handler.g_compliantFulfilledEventRequestId(user),
                "Invariant violated: Request ID should be the same in automated Compliant Fulfilled event as Everest Fulfilled."
            );
        }
    }

    // 10. Fee Transfer Validity:
    //  For any request, the amount of LINK transferred or approved must cover the total fees calculated in _handleFees.
    //  The LINK balance of the contract should decrease by the exact amount transferred to the owner in withdrawFees.

    // 11. Approvals:
    //  LINK approvals to i_everest and the registry must match the required fees for the respective operations.

    // 12. Initialization Protection:
    //  The initialize function can only be called once, and only when the contract is uninitialized (initializer modifier
    //  ensures this).

    // 13. Ownership Management:
    //  The owner can withdraw accumulated fees using withdrawFees.
    //  Only the owner should be able to withdraw the fees (onlyOwner modifier).

    // 14. Incremented Value:
    //  s_incrementedValue can only increase via doSomething, and only if the caller is compliant.
    //  s_automatedIncrement can only increase via performUpkeep, and only if the request was automated and the user is compliant.
}
