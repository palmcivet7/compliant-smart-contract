// Verification of Compliant

using MockEverestConsumer as everest;
using MockForwarder as forwarder;
using MockAutomationRegistry as registry;
using ERC677 as link;

/*//////////////////////////////////////////////////////////////
                            METHODS
//////////////////////////////////////////////////////////////*/
methods {
    function getProxy() external returns(address) envfree;
    function getCompliantFeesToWithdraw() external returns(uint256) envfree;
    function getPendingRequest(address) external returns(Compliant.PendingRequest) envfree;
    function getEverest() external returns(address) envfree;
    function getIsCompliant(address) external returns (bool) envfree;
    function getLink() external returns (address) envfree;
    function getFee() external returns (uint256) envfree;
    function getCompliantFee() external returns (uint256) envfree;
    function getForwarder() external returns (address) envfree;
    function getFeeWithAutomation() external returns (uint256) envfree;
    function getUpkeepId() external returns (uint256) envfree;
    function owner() external returns (address) envfree;

    // External contract functions
    function everest.getLatestFulfilledRequest(address) external returns (IEverestConsumer.Request);
    function everest.oraclePayment() external returns (uint256) envfree;
    function forwarder.getRegistry() external returns (address) envfree;
    function registry.getMinBalance(uint256) external returns (uint96) envfree;
    function link.balanceOf(address) external returns (uint256) envfree;

    // Harness helper functions
    function isAutomation(address,bytes) external returns (bytes) envfree;
    function noAutomation(address,bytes) external returns (bytes) envfree;
    function performData(address,bool) external returns (bytes) envfree;
    // function compress(bytes) external returns (bytes) envfree;
    // function decompress(bytes) external returns (bytes) envfree;

    // LibZip summaries
    function _.cdCompress(bytes memory data) internal => compressionSummary(data) expect (bytes memory);
    function _.cdDecompress(bytes memory data) internal => compressionSummary(data) expect (bytes memory);
}

/*//////////////////////////////////////////////////////////////
                          DEFINITIONS
//////////////////////////////////////////////////////////////*/
definition canChangeState(method f) returns bool = 
	f.selector == sig:onTokenTransfer(address,uint256,bytes).selector || 
	f.selector == sig:requestKycStatus(address,bool,bytes).selector ||
    f.selector == sig:doSomething().selector ||
    f.selector == sig:performUpkeep(bytes).selector ||
    f.selector == sig:withdrawFees().selector ||
    f.selector == sig:initialize(address).selector;

definition canRequestStatus(method f) returns bool = 
	f.selector == sig:onTokenTransfer(address,uint256,bytes).selector || 
	f.selector == sig:requestKycStatus(address,bool,bytes).selector;

definition KYCStatusRequestedEvent() returns bytes32 =
// keccak256(abi.encodePacked("KYCStatusRequested(bytes32,address)"))
    to_bytes32(0x526f9e0c9d2f796e9c96170fef78e1b6b8dba50c6518f1101fdd1380113b9095);

definition KYCStatusRequestFulfilledEvent() returns bytes32 =
// keccak256(abi.encodePacked("KYCStatusRequestFulfilled(bytes32,address,bool)"))
    to_bytes32(0x0b3bad71afd0d65225e0e2be88b41241bc79ec76b33503ff0ca8fb03e47d9d8d);

definition CompliantCheckPassedEvent() returns bytes32 =
// keccak256(abi.encodePacked("CompliantCheckPassed()"))
    to_bytes32(0x55c497259911f7217100faf4dee7dc3263e9067bc83617fa439721b7047574de);

/*//////////////////////////////////////////////////////////////
                           FUNCTIONS
//////////////////////////////////////////////////////////////*/
/// @notice summarize LibZip.cdCompress() and LibZip.cdDecompress()
/// @notice we are not verifying the LibZip library so are ok with such a basic mock
// review - should we be asserting if isPending && data != 0, {PendingRequest.compliantCalldata == compressed(data)} ?
function compressionSummary(bytes data) returns bytes {
    return data;
}

// function cdCompressSummary(bytes data) returns bytes {
//     return compress(data);
// }

// function cdDecompressSummary(bytes data) returns bytes {
//     return decompress(data);
// }

/*//////////////////////////////////////////////////////////////
                             GHOSTS
//////////////////////////////////////////////////////////////*/
/// @notice track total fees earned
persistent ghost mathint g_totalFeesEarned {
    init_state axiom g_totalFeesEarned == 0;
}

/// @notice track total fees withdrawn
persistent ghost mathint g_totalFeesWithdrawn {
    init_state axiom g_totalFeesWithdrawn == 0;
}

/// @notice track address to isPendingRequest
persistent ghost mapping(address => bool) g_pendingRequests {
    init_state axiom forall address a. g_pendingRequests[a] == false;
}

/// @notice track the manual compliant restricted logic's incremented value 
ghost mathint g_manualIncrement {
    init_state axiom g_manualIncrement == 0;
}

/// @notice track the automated compliant restricted logic's incremented value 
ghost mathint g_automatedIncrement {
    init_state axiom g_automatedIncrement == 0;
}

/// @notice track KYCStatusRequested() event emissions
ghost mathint g_kycStatusRequestedEvents {
    init_state axiom g_kycStatusRequestedEvents == 0;
}

/// @notice track KYCStatusRequestFulfilled() event emissions
ghost mathint g_kycStatusRequestFulfilledEvents {
    init_state axiom g_kycStatusRequestFulfilledEvents == 0;
}

/// @notice track CompliantCheckPassed() event emissions
ghost mathint g_compliantCheckPassedEvents {
    init_state axiom g_compliantCheckPassedEvents == 0;
}

/// @notice track isCompliant bool emitted by KYCStatusRequestFulfilled()
ghost bool g_fulfilledRequestIsCompliant {
    init_state axiom g_fulfilledRequestIsCompliant == false;
}

// review - unused ghost
persistent ghost mapping(address => bool) g_fulfilledRequestStatus {
    init_state axiom forall address a. g_fulfilledRequestStatus[a] == false;
}

/*//////////////////////////////////////////////////////////////
                             HOOKS
//////////////////////////////////////////////////////////////*/
/// @notice update g_totalFeesEarned and g_totalFeesWithdrawn ghosts when s_compliantFeesInLink changes
hook Sstore s_compliantFeesInLink uint256 newValue (uint256 oldValue) {
    if (newValue >= oldValue) g_totalFeesEarned = g_totalFeesEarned + newValue - oldValue;
    else g_totalFeesWithdrawn = g_totalFeesWithdrawn + oldValue;
}

/// @notice update g_pendingRequests when s_pendingRequests[address].isPending changes
hook Sstore currentContract.s_pendingRequests[KEY address a].isPending bool newValue (bool oldValue) {
    if (newValue != oldValue) g_pendingRequests[a] = newValue;
}

/// @notice update g_manualIncrement when s_incrementedValue increments
hook Sstore s_incrementedValue uint256 newValue (uint256 oldValue) {
    if (newValue > oldValue) g_manualIncrement = g_manualIncrement + 1;
}

/// @notice update g_automatedIncrement when s_automatedIncrement increments
hook Sstore s_automatedIncrement uint256 newValue (uint256 oldValue) {
    if (newValue > oldValue) g_automatedIncrement = g_automatedIncrement + 1;
}

/// @notice increment g_kycStatusRequestedEvents when KYCStatusRequested() emitted
hook LOG3(uint offset, uint length, bytes32 t0, bytes32 t1, bytes32 t2) {
    if (t0 == KYCStatusRequestedEvent())
        g_kycStatusRequestedEvents = g_kycStatusRequestedEvents + 1;
}

/// @notice increment g_kycStatusRequestFulfilledEvents when KYCStatusRequestFulfilled emitted
/// @notice set g_fulfilledRequestIsCompliant to true when fulfilled event isCompliant
hook LOG4(uint offset, uint length, bytes32 t0, bytes32 t1, bytes32 t2, bytes32 t3) {
    if (t0 == KYCStatusRequestFulfilledEvent()) 
        g_kycStatusRequestFulfilledEvents = g_kycStatusRequestFulfilledEvents + 1;

    if (t0 == KYCStatusRequestFulfilledEvent() && t3 != to_bytes32(0)) 
        g_fulfilledRequestIsCompliant = true;
}

/// @notice increment g_compliantCheckPassedEvents when CompliantCheckPassed() emitted
hook LOG1(uint offset, uint length, bytes32 t0) {
    if (t0 == CompliantCheckPassedEvent()) 
        g_compliantCheckPassedEvents = g_compliantCheckPassedEvents + 1;
}

/*//////////////////////////////////////////////////////////////
                           INVARIANTS
//////////////////////////////////////////////////////////////*/
/// @notice total fees to withdraw must equal total fees earned minus total fees already withdrawn
invariant feesAccounting()
    to_mathint(getCompliantFeesToWithdraw()) == g_totalFeesEarned - g_totalFeesWithdrawn;

/// @notice pending requests should only be true whilst waiting for Chainlink Automation
invariant pendingRequests(address a)
    getPendingRequest(a).isPending == g_pendingRequests[a];

/*//////////////////////////////////////////////////////////////
                             RULES
//////////////////////////////////////////////////////////////*/
/// @notice direct calls to methods that change state should revert 
rule directCallsRevert(method f) filtered {f -> canChangeState(f)} {
    env e;
    calldataarg args;

    require currentContract != getProxy();

    f@withrevert(e, args);
    assert lastReverted;
}

/// @notice onTokenTransfer should revert if not called by LINK token
rule onTokenTransfer_revertsWhen_notLink() {
    env e;
    calldataarg args;

    require e.msg.sender != getLink();

    onTokenTransfer@withrevert(e, args);
    assert lastReverted;
}

/// @notice onTokenTransfer should revert if fee amount is insufficient
rule onTokenTransfer_revertsWhen_insufficientFee() {
    env e;
    address user;
    uint256 amount;
    bytes arbitraryData;
    bytes data;
    require data == isAutomation(user, arbitraryData) || data == noAutomation(user, arbitraryData);

    if (data == isAutomation(user, arbitraryData)) require amount < getFeeWithAutomation();
    else require amount < getFee();

    onTokenTransfer@withrevert(e, user, amount, data);
    assert lastReverted;
}

/// @notice checkLog is simulated offchain by CLA nodes and should revert
rule checkLogReverts() {
    env e;
    calldataarg args;
    
    require e.tx.origin != 0;
    require e.tx.origin != 0x1111111111111111111111111111111111111111;

    checkLog@withrevert(e, args);
    assert lastReverted;
}

/// @notice initialize should only be callable once and then it should always revert
rule initializeReverts() {
    env e;
    calldataarg args;

    initialize(e, args);
    initialize@withrevert(e, args);
    assert lastReverted;
}

/// @notice performUpkeep should revert if not called by the forwarder
rule performUpkeep_revertsWhen_notForwarder() {
    env e;
    calldataarg args;

    require e.msg.sender != getForwarder();

    performUpkeep@withrevert(e, args);
    assert lastReverted;
}

/// @notice doSomething should revert if caller is not compliant
rule doSomething_revertsWhen_notCompliant() {
    env e;
    calldataarg args;

    require !getIsCompliant(e.msg.sender);

    doSomething@withrevert(e, args);
    assert lastReverted;
}

/// @notice fee calculation for requestKycStatus should be correct
rule requestKycStatus_feeCalculation() {
    env e;
    address user;
    bool isAutomation;
    bytes arbitraryData;
    require link == getLink();
    require e.msg.sender != getEverest();
    require e.msg.sender != currentContract;
    if (isAutomation) require e.msg.sender != forwarder.getRegistry();

    uint256 balance_before = link.balanceOf(e.msg.sender);

    requestKycStatus(e, user, isAutomation, arbitraryData);

    uint256 balance_after = link.balanceOf(e.msg.sender);

    if (isAutomation) assert balance_before == balance_after + getFeeWithAutomation();
    else assert balance_before == balance_after + getFee();
}

/// @notice fee calculation for onTokenTransfer should be correct
rule onTokenTransfer_feeCalculation() {
    env e;
    address user;
    uint256 amount;
    bytes arbitraryData;
    bytes data;
    require data == isAutomation(user, arbitraryData) || data == noAutomation(user, arbitraryData);

    onTokenTransfer(e, user, amount, data);

    if (data == isAutomation(user, arbitraryData)) assert amount >= getFeeWithAutomation();
    else assert amount >= getFee();
}

/// @notice only owner should be able to call withdrawFees
rule withdrawFees_revertsWhen_notOwner() {
    env e;
    require currentContract == getProxy();
    require e.msg.sender != owner();

    withdrawFees@withrevert(e);
    assert lastReverted;
}

/// @notice LINK balance of the contract should decrease by the exact amount transferred to the owner in withdrawFees
rule withdrawFees_balanceIntegrity() {
    env e;
    require e.msg.sender != currentContract;
    require link == getLink();
    uint256 feesToWithdraw = getCompliantFeesToWithdraw();

    uint256 balance_before = link.balanceOf(currentContract);
    withdrawFees(e);
    uint256 balance_after = link.balanceOf(currentContract);

    assert balance_after == balance_before - feesToWithdraw;
}

/// @notice automated requests made through onTokenTransfer should add funds to Chainlink registry
rule onTokenTransfer_automatedRequest_fundsRegistry() {
    env e;
    address user;
    uint256 amount;
    bytes arbitraryData;
    bytes data;
    require data == isAutomation(user, arbitraryData);
    require link == getLink();
    require forwarder == getForwarder();
    require registry == forwarder.getRegistry();
    uint256 minBalance = registry.getMinBalance(getUpkeepId());

    uint256 balance_before = link.balanceOf(registry);
    require balance_before + minBalance <= max_uint;

    onTokenTransfer(e, user, amount, data);

    uint256 balance_after = link.balanceOf(registry);

    assert balance_after == balance_before + minBalance;
}

/// @notice automated requests made with requestKycStatus should add funds to Chainlink registry
rule requestKycStatus_automatedRequest_fundsRegistry() {
    env e;
    address user;
    bool isAutomation;
    bytes arbitraryData;
    require link == getLink();
    require e.msg.sender != getEverest();
    require e.msg.sender != currentContract;
    require isAutomation;
    require e.msg.sender != forwarder.getRegistry();
    uint256 minBalance = registry.getMinBalance(getUpkeepId());

    uint256 balance_before = link.balanceOf(registry);
    require balance_before + minBalance <= max_uint;

    requestKycStatus(e, user, isAutomation, arbitraryData);

    uint256 balance_after = link.balanceOf(registry);

    assert balance_after == balance_before + minBalance;
}

/// @notice KYCStatusRequested event is emitted for every request
rule requests_emit_events(method f) filtered {f -> canRequestStatus(f)} {
    env e;
    calldataarg args;

    require g_kycStatusRequestedEvents == 0;

    f(e, args);

    assert g_kycStatusRequestedEvents == 1;
}

/// @notice KYCStatusRequestFulfilled event is emitted for every fulfilled *AUTOMATED* request
rule fulfilledAutomatedRequest_emits_event() {
    env e;
    calldataarg args;

    require g_kycStatusRequestFulfilledEvents == 0;

    performUpkeep(e, args);

    assert g_kycStatusRequestFulfilledEvents == 1;
}

/// @notice CompliantCheckPassed() should only be emitted for compliant users
rule compliantCheckPassed_emits_for_compliantUser() {
    env e;
    calldataarg args;

    require g_compliantCheckPassedEvents == 0;
    require g_fulfilledRequestIsCompliant == false;

    performUpkeep(e, args);

    assert g_compliantCheckPassedEvents == 1 => g_fulfilledRequestIsCompliant;
    assert g_compliantCheckPassedEvents == 0 => !g_fulfilledRequestIsCompliant;
}

/// @notice Compliant restricted state change should only execute on behalf of compliant users
rule compliantRestrictedLogic_manualExecution() {
    env e;

    require g_manualIncrement == 0;

    doSomething(e);

    assert g_manualIncrement == 1 => getIsCompliant(e.msg.sender);
    assert g_manualIncrement == 0 => !getIsCompliant(e.msg.sender);
}

/// @notice automated compliant restricted state change should only execute on behalf of compliant user
rule compliantRestrictedLogic_automatedExecution() {
    env e;
    calldataarg args;
    address user; bool isCompliant;

    require g_automatedIncrement == 0;

    bytes performData = performData(user, isCompliant);

    performUpkeep(e, performData);

    assert g_automatedIncrement == 1 => isCompliant;
    assert g_automatedIncrement == 0 => !isCompliant;
}

/// @notice compliant calldata passed to requestKycStatus should only be stored whilst automated request is pending
rule requestKycStatus_compliantCalldata_storedCorrectly() {
    env e;
    address user;
    bool isAutomation;
    bytes arbitraryData;
    require isAutomation;

    Compliant.PendingRequest request_before = getPendingRequest(user);
    require !request_before.isPending;

    requestKycStatus(e, user, isAutomation, arbitraryData);

    Compliant.PendingRequest request_after = getPendingRequest(user);

    assert request_after.compliantCalldata == compressionSummary(arbitraryData) => request_after.isPending;
    assert !request_after.isPending => request_after.compliantCalldata.length == 0;
}

/// @notice compliant calldata passed to onTokenTransfer should only be stored whilst automated request is pending
rule onTokenTransfer_compliantCalldata_storedCorrectly() {
    env e;
    address user;
    uint256 amount;
    bytes arbitraryData;
    bytes data;
    require data == isAutomation(user, arbitraryData);

    Compliant.PendingRequest request_before = getPendingRequest(user);
    require !request_before.isPending;

    onTokenTransfer(e, user, amount, data);

    Compliant.PendingRequest request_after = getPendingRequest(user);

    assert request_after.compliantCalldata == compressionSummary(arbitraryData) => request_after.isPending;
    assert !request_after.isPending => request_after.compliantCalldata.length == 0;
}

/// @notice requests must fund Everest with correct fee amount
rule requests_fundEverest(method f) filtered {f -> canRequestStatus(f)} {
    env e;
    calldataarg args;
    require link == getLink();
    require everest == getEverest();
    require e.msg.sender != everest;
    uint256 fee = everest.oraclePayment();

    uint256 balance_before = link.balanceOf(everest);

    require balance_before + fee <= max_uint;

    f(e, args);

    uint256 balance_after = link.balanceOf(everest);

    assert balance_after == balance_before + fee;
}