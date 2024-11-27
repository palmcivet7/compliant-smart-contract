// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Compliant, LinkTokenInterface, Ownable} from "./Compliant.sol";
import {IAutomationRegistrar, RegistrationParams} from "./interfaces/IAutomationRegistrar.sol";

/// @notice The purpose of this contract is to deploy the Compliant contract in such a way to store
/// Chainlink Automation variables (upkeepId and forwarder address) as immutable.
contract CompliantFactory is Ownable {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @dev 3 LINK is required by the owner of the contract to deploy Compliant and fund initial Automation
    uint256 internal constant LINK_AUTOMATION_REGISTRATION_AMOUNT = 3e18;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/
    function deployCompliant(address everest, address link, address priceFeed, address automation, address registrar)
        external
        onlyOwner
        returns (Compliant)
    {
        LinkTokenInterface(link).transferFrom(msg.sender, address(this), LINK_AUTOMATION_REGISTRATION_AMOUNT);
        // Compliant compliant = new Compliant();
    }
}
