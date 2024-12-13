// Verification of Compliant

using EverestConsumer as everest;

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
    function getForwarder() external returns (address) envfree;
    function getFeeWithAutomation() external returns (uint256) envfree;
    function checkLog(Compliant.Log,bytes) external returns (bool,bytes);
    function initialize(address) external envfree;

    // Everest function
    function everest.getLatestFulfilledRequest(address) external returns (IEverestConsumer.Request);

    // Harness helper functions
    function isAutomation(address,bytes) external returns (bytes) envfree;
    function noAutomation(address,bytes) external returns (bytes) envfree;
    // function getEverestCompliance(address) external returns (bool) envfree;
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

/*//////////////////////////////////////////////////////////////
                             HOOKS
//////////////////////////////////////////////////////////////*/
hook Sstore s_compliantFeesInLink uint256 newValue (uint256 oldValue) {
    if (newValue >= oldValue) g_totalFeesEarned = g_totalFeesEarned + newValue - oldValue;
    else g_totalFeesWithdrawn = g_totalFeesWithdrawn + oldValue;
}

hook Sstore currentContract.s_pendingRequests[KEY address a].isPending bool newValue (bool oldValue) {
    if (newValue != oldValue) g_pendingRequests[a] = newValue;
}

/*//////////////////////////////////////////////////////////////
                           INVARIANTS
//////////////////////////////////////////////////////////////*/
invariant feesAccounting()
    to_mathint(getCompliantFeesToWithdraw()) == g_totalFeesEarned - g_totalFeesWithdrawn;

invariant pendingRequests(address a)
    getPendingRequest(a).isPending == g_pendingRequests[a];

// invariant compliantStatus(address a)
//     getIsCompliant(a) == getEverestCompliance(a);

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

// /// @notice onTokenTransfer should revert if fee amount is insufficient
// rule onTokenTransfer_revertsWhen_insufficientFee_noAutomation() {
//     env e;
//     address addr;
//     uint256 amount;
//     bytes compliantCalldata;
//     // bytes data = noAutomation(addr, compliantCalldata);
//     bytes data;

//     // require amount < getFee();
//     require e.msg.sender == getLink();
//     require currentContract == getProxy();
//     require e.msg.value == 0;

//     onTokenTransfer@withrevert(e, addr, amount, data);
//     assert lastReverted => 
//         (amount < getFee() && data == noAutomation(addr, compliantCalldata)) ||
//         (amount < getFeeWithAutomation() && data == isAutomation(addr, compliantCalldata));
// }

/// @notice onTokenTransfer should revert if fee amount is insufficient
rule onTokenTransfer_revertsWhen_insufficientFee_noAutomation() {
    env e;
    address addr;
    uint256 amount;
    bytes compliantCalldata;
    bytes data = noAutomation(addr, compliantCalldata);

    require amount < getFee();

    onTokenTransfer@withrevert(e, addr, amount, data);
    assert lastReverted;
}

// /// @notice onTokenTransfer should revert if fee amount is insufficient
// rule onTokenTransfer_revertsWhen_insufficientFee_withAutomation() {
//     env e;
//     address addr;
//     uint256 amount;
//     bytes compliantCalldata;
//     bytes data = isAutomation(addr, compliantCalldata);

//     require amount < getFeeWithAutomation();

//     onTokenTransfer@withrevert(e, addr, amount, data);
//     assert lastReverted;
// }

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