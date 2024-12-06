/// Verification of Compliant

/*//////////////////////////////////////////////////////////////
                            METHODS
//////////////////////////////////////////////////////////////*/
methods {
    function getProxy() external returns(address) envfree;
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