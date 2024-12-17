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
    
    // review these
    function checkLog(Compliant.Log,bytes) external returns (bool,bytes);
    function initialize(address) external envfree;

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

/*//////////////////////////////////////////////////////////////
                           FUNCTIONS
//////////////////////////////////////////////////////////////*/
function getEverestCompliance(address user) returns bool {
    env e;
    require everest == getEverest();
    IEverestConsumer.Request request = everest.getLatestFulfilledRequest(e, user);
    return request.isKYCUser;
}

/*//////////////////////////////////////////////////////////////
                             GHOSTS
//////////////////////////////////////////////////////////////*/
persistent ghost mathint g_totalFeesEarned {
    init_state axiom g_totalFeesEarned == 0;
}

persistent ghost mathint g_totalFeesWithdrawn {
    init_state axiom g_totalFeesWithdrawn == 0;
}

persistent ghost mapping(address => bool) g_pendingRequests {
    init_state axiom forall address a. g_pendingRequests[a] == false;
}

persistent ghost mathint g_manualIncrement {
    init_state axiom g_manualIncrement == 0;
}

/*//////////////////////////////////////////////////////////////
                             HOOKS
//////////////////////////////////////////////////////////////*/
/// @notice everytime the value stored in `s_compliantFeesInLink` changes, we track it in the ghosts
hook Sstore s_compliantFeesInLink uint256 newValue (uint256 oldValue) {
    if (newValue >= oldValue) g_totalFeesEarned = g_totalFeesEarned + newValue - oldValue;
    else g_totalFeesWithdrawn = g_totalFeesWithdrawn + oldValue;
}

/// @notice track everytime the `PendingRequest.isPending` mapped to a user in `s_pendingRequests` changes
hook Sstore currentContract.s_pendingRequests[KEY address a].isPending bool newValue (bool oldValue) {
    if (newValue != oldValue) g_pendingRequests[a] = newValue;
}

hook Sstore s_incrementedValue uint256 newValue (uint256 oldValue) {
    if (newValue > oldValue) g_manualIncrement = g_manualIncrement + 1;
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
    calldataarg args;

    initialize(args);
    initialize@withrevert(args);
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

/// manual incremented value consistency
/// automated incremented value consistency
// event consistency:
/// KYCStatusRequested event is emitted for every request
/// KYCStatusRequestFulfilled event emitted for fulfilled *AUTOMATED* requests
/// KYCStatusRequestFulfilled event should emit the correct isCompliant status

/// compliant calldata stored for user should only be there whilst request is pending

/// Automation-related requests should add funds to the Chainlink registry via registry.addFunds
rule automatedRequests_addFunds_toRegistry(method f) filtered {f -> canRequestStatus(f)} {
    env e;
    calldataarg args;

    require link == getLink();
    require forwarder == getForwarder();
    require registry == forwarder.getRegistry();
    uint256 minBalance = registry.getMinBalance(getUpkeepId());

    uint256 balance_before = link.balanceOf(registry);

    // we need to make sure the isAutomation bool is true
    f(e, args);

    uint256 balance_after = link.balanceOf(registry);

    // can we imply something here => 
    assert balance_after == balance_before + minBalance;


    /// 
    /// update ghost: g_linkAddedToRegistry += registry.getMinBalance(getUpkeepId());
    /// assert link.balanceOf(registry) == g_linkAddedToRegistry

}
