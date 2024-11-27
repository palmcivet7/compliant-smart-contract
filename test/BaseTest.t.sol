// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {Compliant} from "../../src/Compliant.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockLinkToken} from "./mocks/MockLinkToken.sol";
import {MockEverestConsumer} from "./mocks/MockEverestConsumer.sol";
import {MockAutomationConsumer} from "./mocks/MockAutomationConsumer.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

contract BaseTest is Test {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 internal constant USER_LINK_BALANCE = 10e18;
    uint256 internal constant DEPLOYER_BALANCE = 1e18;

    uint256 internal constant STARTING_BLOCK = 7155638;
    uint256 internal constant MAINNET_STARTING_BLOCK = 21278732;

    Compliant internal compliant;
    address internal everest;
    address internal link;
    address internal linkUsdFeed;
    address internal automation;
    address internal registrar;
    address internal swapRouter;
    address internal linkEthFeed;

    // address internal deployer = makeAddr("deployer");
    address internal deployer = vm.envAddress("DEPLOYER_ADDRESS");
    address internal user = makeAddr("user");

    uint256 internal ethSepoliaFork;
    uint256 internal ethMainnetFork;

    MockEverestConsumer internal everestConsumer;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public virtual {
        /// @dev fork eth sepolia
        // ethSepoliaFork = vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"), STARTING_BLOCK);
        ethMainnetFork = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), MAINNET_STARTING_BLOCK);

        /// @dev get Compliant constructor args from HelperConfig
        HelperConfig config = new HelperConfig();
        (everest, link, linkUsdFeed, automation, registrar, swapRouter, linkEthFeed) = config.activeNetworkConfig();

        /// @dev deploy mock Everest consumer
        everestConsumer = new MockEverestConsumer(link);

        /// @dev deal LINK to user
        deal(link, user, USER_LINK_BALANCE);

        /// @dev deal ETH to deployer
        vm.deal(deployer, DEPLOYER_BALANCE);

        /// @dev deploy Compliant
        vm.prank(deployer);
        compliant = new Compliant{value: DEPLOYER_BALANCE}(
            address(everestConsumer), link, linkUsdFeed, automation, registrar, swapRouter, linkEthFeed
        );
    }

    /// @notice Empty test function to ignore file in coverage report
    function test_baseTest() public {}

    /*//////////////////////////////////////////////////////////////
                                UTILITY
    //////////////////////////////////////////////////////////////*/
    /// @dev set the user to compliant
    function _setUserToCompliant(address _user) internal {
        MockEverestConsumer(everest).setLatestFulfilledRequest(
            false, true, true, msg.sender, _user, uint40(block.timestamp)
        );
    }

    /// @dev set the user to pending request
    function _setUserPendingRequest(bytes memory compliantCalldata) internal {
        uint256 amount = compliant.getFeeWithAutomation();
        bool isAutomation = true;
        bytes memory data = abi.encode(user, isAutomation, compliantCalldata);
        vm.prank(user);
        LinkTokenInterface(link).transferAndCall(address(compliant), amount, data);

        Compliant.PendingRequest memory request = compliant.getPendingRequest(user);
        assertTrue(request.isPending);
    }
}
