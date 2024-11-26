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
        address registrar;
    }

    NetworkConfig public activeNetworkConfig;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() {
        if (block.chainid == 137) {
            activeNetworkConfig = getPolygonConfig();
        } else if (block.chainid == 1) {
            activeNetworkConfig = getEthMainnetConfig();
        } else if (block.chainid == 11155111) {
            activeNetworkConfig = getEthSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 GETTER
    //////////////////////////////////////////////////////////////*/
    function getPolygonConfig() public pure returns (NetworkConfig memory) {}

    function getEthMainnetConfig() public pure returns (NetworkConfig memory) {}

    function getEthSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            everest: 0x2465e36f7fe01a3cC88906cC00D0486AA03dd200, // deployed mock
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            priceFeed: 0xc59E3633BAAC79493d908e63626716e204A45EdF,
            automation: 0x86EFBD0b6736Bed994962f9797049422A3A8E8Ad,
            registrar: 0xb0E49c5D0d05cbc241d68c05BC5BA1d1B7B72976
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        MockLinkToken mockLink = new MockLinkToken();
        MockEverestConsumer mockEverest = new MockEverestConsumer(address(mockLink));
        MockV3Aggregator mockPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_ANSWER);
        MockAutomationConsumer mockAutomation = new MockAutomationConsumer(address(mockLink));

        return NetworkConfig({
            everest: address(mockEverest),
            link: address(mockLink),
            priceFeed: address(mockPriceFeed),
            automation: address(mockAutomation),
            registrar: address(0)
        });
    }
}
