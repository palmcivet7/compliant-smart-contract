// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {MockEverestConsumer} from "../test/mocks/MockEverestConsumer.sol";
import {MockLinkToken} from "../test/mocks/MockLinkToken.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {MockAutomationConsumer} from "../test/mocks/MockAutomationConsumer.sol";

contract HelperConfig is Script {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint8 constant DECIMALS = 8;
    int256 constant INITIAL_ANSWER = 15 * 1e8; // $15/LINK

    /*//////////////////////////////////////////////////////////////
                             NETWORK CONFIG
    //////////////////////////////////////////////////////////////*/
    struct NetworkConfig {
        address everest;
        address link;
        address priceFeed;
        address automation;
    }
    // address forwarder;
    // uint256 claSubId;

    NetworkConfig public activeNetworkConfig;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() {
        if (block.chainid == 137) {
            activeNetworkConfig = getPolygonConfig();
        } else if (block.chainid == 1) {
            activeNetworkConfig = getEthMainnetConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 GETTER
    //////////////////////////////////////////////////////////////*/
    function getPolygonConfig() public pure returns (NetworkConfig memory) {}

    function getEthMainnetConfig() public pure returns (NetworkConfig memory) {}

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        MockEverestConsumer mockEverest = new MockEverestConsumer();
        MockLinkToken mockLink = new MockLinkToken();
        MockV3Aggregator mockPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_ANSWER);
        MockAutomationConsumer mockAutomation = new MockAutomationConsumer(address(mockLink));

        return NetworkConfig({
            everest: address(mockEverest),
            link: address(mockLink),
            priceFeed: address(mockPriceFeed),
            automation: address(mockAutomation)
        });
    }
}
