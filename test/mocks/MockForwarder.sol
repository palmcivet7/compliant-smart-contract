// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IAutomationRegistryConsumer} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/IAutomationRegistryConsumer.sol";

contract MockForwarder {
    IAutomationRegistryConsumer internal immutable i_registry;

    constructor(address registry) {
        i_registry = IAutomationRegistryConsumer(registry);
    }

    function getRegistry() external view returns (IAutomationRegistryConsumer) {
        return i_registry;
    }
}
