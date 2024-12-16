// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Compliant} from "../../src/Compliant.sol";
import {IEverestConsumer} from "lib/everest-chainlink-consumer/contracts/EverestConsumer.sol";

contract Harness is Compliant {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address everest, address link, address linkUsdFeed, address forwarder, uint256 upkeepId, address proxy)
        Compliant(everest, link, linkUsdFeed, forwarder, upkeepId, proxy)
    {}

    /*//////////////////////////////////////////////////////////////
                                UTILITY
    //////////////////////////////////////////////////////////////*/
    /// @dev create data to pass to onTokenTransfer with Automation
    function isAutomation(address user, bytes memory compliantCalldata) external returns (bytes memory) {
        return abi.encode(user, true, compliantCalldata);
    }

    /// @dev create data to pass to onTokenTransfer with no Automation
    function noAutomation(address user, bytes memory compliantCalldata) external returns (bytes memory) {
        return abi.encode(user, false, compliantCalldata);
    }
}
