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
        address linkUsdFeed;
        address automation;
        address registrar;
        address swapRouter;
        address linkEthFeed;
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

    function getEthMainnetConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            everest: address(0), // deployed mock
            link: 0x514910771AF9Ca656af840dff83E8264EcF986CA,
            linkUsdFeed: 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c,
            automation: 0x6593c7De001fC8542bB1703532EE1E5aA0D458fD,
            registrar: 0x6B0B234fB2f380309D47A7E9391E29E9a179395a,
            swapRouter: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D,
            linkEthFeed: 0xDC530D9457755926550b59e8ECcdaE7624181557
        });
    }

    function getEthSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            everest: 0x2465e36f7fe01a3cC88906cC00D0486AA03dd200, // deployed mock
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            linkUsdFeed: 0xc59E3633BAAC79493d908e63626716e204A45EdF,
            automation: 0x86EFBD0b6736Bed994962f9797049422A3A8E8Ad,
            registrar: 0xb0E49c5D0d05cbc241d68c05BC5BA1d1B7B72976,
            swapRouter: 0xB26B2De65D07eBB5E54C7F6282424D3be670E1f0,
            linkEthFeed: 0x42585eD362B3f1BCa95c640FdFf35Ef899212734
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
            linkUsdFeed: address(mockPriceFeed),
            automation: address(mockAutomation),
            registrar: address(0),
            swapRouter: address(0),
            linkEthFeed: address(0)
        });
    }
}
