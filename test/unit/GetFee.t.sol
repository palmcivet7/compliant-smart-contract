// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";

contract GetFeeTest is BaseTest {
    function test_compliant_getFee() public {
        /// @dev set the price of LINK to $1
        int256 oneDollar = 100_000_000;
        MockV3Aggregator(linkUsdFeed).updateAnswer(oneDollar);

        /// @dev so that we can accurately calculate our expected fee is 50c worth of LINK
        uint256 totalFee = compliant.getFee();
        uint256 compliantFee = totalFee - IEverestConsumer(everest).oraclePayment();
        uint256 expectedFee = 5 * 1e17;

        assertEq(compliantFee, expectedFee);
    }
}
