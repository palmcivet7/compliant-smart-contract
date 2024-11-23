// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {Compliant} from "../../src/Compliant.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockLinkToken} from "../mocks/MockLinkToken.sol";

contract BaseTest is Test {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    Compliant internal compliant;
    address internal everest;
    address internal link;
    address internal priceFeed;
    address internal automation;
    address internal forwarder = makeAddr("forwarder");
    uint256 internal claSubId = 1;

    address internal deployer = makeAddr("deployer");
    address internal user = makeAddr("user");

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public virtual {
        vm.startPrank(deployer);
        HelperConfig config = new HelperConfig();
        (everest, link, priceFeed, automation) = config.activeNetworkConfig();

        /// @dev mints total supply to msg.sender (deployer)
        MockLinkToken(link).initializeMockLinkToken();

        compliant = new Compliant(everest, link, priceFeed, automation, forwarder, claSubId);
        vm.stopPrank();
    }
}
