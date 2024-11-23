// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest, LinkTokenInterface} from "../BaseTest.t.sol";
import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";

contract WithdrawFeesTest is BaseTest {
    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public override {
        BaseTest.setUp();

        uint256 approvalAmount = compliant.getFee();

        vm.prank(user);
        LinkTokenInterface(link).approve(address(compliant), approvalAmount);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/
    function test_compliant_withdrawFees() public {
        vm.prank(user);
        uint256 fee = compliant.requestKycStatus(user, false); // false for no automation
        uint256 compliantFee = fee - IEverestConsumer(everest).oraclePayment();

        address owner = compliant.owner();
        uint256 balanceBefore = LinkTokenInterface(link).balanceOf(owner);

        uint256 feesToWithdrawBefore = compliant.getCompliantFeesToWithdraw();
        assertEq(compliantFee, feesToWithdrawBefore);

        vm.prank(owner);
        compliant.withdrawFees();

        uint256 balanceAfter = LinkTokenInterface(link).balanceOf(owner);
        uint256 feesToWithdrawAfter = compliant.getCompliantFeesToWithdraw();
        assertEq(feesToWithdrawAfter, 0);
        assertEq(balanceAfter, balanceBefore + compliantFee);
    }

    function test_compliant_withdrawFees_revertsWhen_notOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        compliant.withdrawFees();
    }
}
