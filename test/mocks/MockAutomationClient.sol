// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ILogAutomation, Log} from "@chainlink/contracts/src/v0.8/automation/interfaces/ILogAutomation.sol";

/// @notice This contract is needed to register Chainlink Automation for testing
contract MockAutomationClient is ILogAutomation {
    function checkLog(Log calldata log, bytes memory checkData)
        external
        returns (bool upkeepNeeded, bytes memory performData)
    {}

    function performUpkeep(bytes calldata performData) external {}
}
