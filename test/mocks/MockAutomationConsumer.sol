// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IAutomationRegistryConsumer} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/IAutomationRegistryConsumer.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

contract MockAutomationConsumer is IAutomationRegistryConsumer {
    LinkTokenInterface internal immutable i_link;

    uint96 balance;
    uint96 minBalance;

    constructor(address link) {
        i_link = LinkTokenInterface(link);
    }

    function setMinBalance(uint96 _minBalance) external {
        minBalance = _minBalance;
    }

    function getBalance(uint256 /* id */ ) external view override returns (uint96) {
        return balance;
    }

    function getMinBalance(uint256 /* id */ ) external view override returns (uint96) {
        return minBalance;
    }

    function cancelUpkeep(uint256 id) external override {}

    function pauseUpkeep(uint256 id) external override {}

    function unpauseUpkeep(uint256 id) external override {}

    function updateCheckData(uint256 id, bytes calldata newCheckData) external {}

    function addFunds(uint256, /* id */ uint96 amount) external override {
        i_link.transferFrom(msg.sender, address(this), amount);
    }

    function withdrawFunds(uint256 id, address to) external override {}

    /// @notice Empty test function to ignore file in coverage report
    function test_mockAutomation() public {}
}
