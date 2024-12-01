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

contract Invariant is StdInvariant, BaseTest {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @dev value returned by registry.getMinBalance()
    // @review consider updating this randomly to sensibly bound values
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
        handler = new Handler(compliant, address(compliantProxy), deployer, link, forwarder);

        /// @dev define appropriate function selectors
        bytes4[] memory selectors = new bytes4[](1);
        // selectors[0] = Handler.onTokenTransfer.selector;
        // selectors[1] = Handler.requestKycStatus.selector;
        // selectors[2] = Handler.doSomething.selector;
        // selectors[3] = Handler.withdrawFees.selector;
        selectors[0] = Handler.externalImplementationCalls.selector;

        /// @dev target handler and appropriate function selectors
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /*//////////////////////////////////////////////////////////////
                               INVARIANTS
    //////////////////////////////////////////////////////////////*/
    function invariant_checkSomething() public {
        assertTrue(true);
    }

    // what are our invariants?

    // 1. Proxy Protection:
    //  All external functions should be callable only through the proxy (onlyProxy modifier ensures this).
    //  Direct calls to the implementation contract should fail.
    function invariant_onlyProxy_noDirectCallsSucceed() public view {
        assertEq(handler.g_directCallSuccesses(), 0, "Invariant violated: Direct calls should never succeed");
    }

    function invariant_onlyProxy_directCallsRevert() public view {
        assertEq(
            handler.g_directImplementationCalls(),
            handler.g_directCallReverts(),
            "Invariant violated: All direct calls should revert"
        );
    }

    // 2. Pending Request Management:
    //  For any user address, at most one pending request can exist at a time (s_pendingRequests[user].isPending).
    //  If a pending request is fulfilled, isPending must be set to false.

    // 3. Fees Accounting:
    //  The total s_compliantFeesInLink should always equal the cumulative LINK collected from fees minus any
    //  LINK withdrawn using withdrawFees.

    // 4. KYC Status Consistency:
    //  A user marked as compliant (_isCompliant(user)) must have their latest fulfilled KYC request indicating isKYCUser = true.

    // 5. Fee Calculation:
    //  The fee for KYC requests should always match the sum of: _calculateCompliantFee(), i_everest.oraclePayment(),
    //  Automation fees (if applicable).

    // 6. Compliance Logic:
    //  Only compliant users can call doSomething successfully.
    //  The _executeCompliantLogic function must only execute if the user is marked as compliant.

    // 7. Upkeep Execution: NOTE: THIS WOULD REQUIRE LOCAL CHAINLINK AUTOMATION SIMULATOR
    //  performUpkeep should only process requests where checkLog indicates that upkeepNeeded is true.
    //  Automation-related requests (isAutomated = true) should add funds to the Chainlink registry via registry.addFunds.

    // 8. Forwarder Protection:
    //  Only the registered forwarder (i_forwarder) can call performUpkeep.

    // 9. Event Consistency:
    //  Every KYC status request emits a KYCStatusRequested event with the correct everestRequestId and user.
    //  Fulfilled requests emit KYCStatusRequestFulfilled with the correct requestId, user, and isCompliant status.

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
