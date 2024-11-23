// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {ILogAutomation, Log} from "@chainlink/contracts/src/v0.8/automation/interfaces/ILogAutomation.sol";
import {AutomationBase} from "@chainlink/contracts/src/v0.8/automation/AutomationBase.sol";
import {IAutomationRegistryConsumer} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/IAutomationRegistryConsumer.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC677Receiver} from "@chainlink/contracts/src/v0.8/shared/interfaces/IERC677Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice A template contract for requesting and getting the KYC compliant status of an address.
contract Compliant is ILogAutomation, AutomationBase, Ownable, IERC677Receiver {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error Compliant__OnlyLinkToken();
    error Compliant__InsufficientLinkTransferAmount(uint256 insufficientAmount, uint256 requiredAmount);
    error Compliant__NonCompliantUser(address nonCompliantUser);
    error Compliant__PendingRequestExists(address pendingRequestedUser);
    error Compliant__OnlyForwarder();

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @dev 18 token decimals
    uint256 internal constant WAD_PRECISION = 1e18;
    /// @dev $0.50 to 8 decimals because price feeds have 8 decimals
    uint256 internal constant COMPLIANT_FEE = 5_000_000;

    /// @dev Everest Chainlink Consumer
    IEverestConsumer internal immutable i_everest;
    /// @dev LINK token contract
    LinkTokenInterface internal immutable i_link;
    /// @dev Chainlink PriceFeed for LINK/USD
    AggregatorV3Interface internal immutable i_priceFeed;
    /// @dev Chainlink Automation Consumer
    IAutomationRegistryConsumer internal immutable i_automation;
    /// @dev Chainlink Automation forwarder
    address internal immutable i_forwarder;
    /// @dev Chainlink Automation subscription ID
    uint256 internal immutable i_claSubId;

    /// @dev tracks the accumulated fees for this contract in LINK
    uint256 internal s_compliantFeesInLink;
    /// @dev maps the address of the requested user to the last request id
    // @audit-review is this really needed?
    mapping(address user => bytes32 lastRequestId) internal s_lastEverestRequestId;
    /// @dev tracks pending kyc status requests
    mapping(address user => bool requestPending) internal s_pendingRequests;

    /// @notice These two values are included for demo purposes
    /// @dev This can only be incremented by users who have completed KYC
    uint256 internal s_incrementedValue;
    /// @dev this can only be incremented by performUpkeep if a requested user is compliant
    uint256 internal s_automatedIncrement;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /// @dev emitted when KYC status of an address is requested
    event KYCStatusRequested(bytes32 indexed everestRequestId, address indexed user);
    /// @dev emitted when KYC status of an address is fulfilled
    event KYCStatusRequestFulfilled(bytes32 indexed everestRequestId, address indexed user, bool indexed isCompliant);

    /// @notice included for demo purposes
    event CompliantCheckPassed();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @param everest Everest Chainlink consumer
    /// @param link LINK token
    /// @param priceFeed LINK/USD Chainlink PriceFeed
    /// @param automation Chainlink Automation consumer
    /// @param forwarder Chainlink Automation forwarder
    /// @param claSubId Chainlink Automation subscription ID
    constructor(
        address everest,
        address link,
        address priceFeed,
        address automation,
        address forwarder,
        uint256 claSubId
    ) Ownable(msg.sender) {
        i_everest = IEverestConsumer(everest);
        i_link = LinkTokenInterface(link);
        i_priceFeed = AggregatorV3Interface(priceFeed);
        i_automation = IAutomationRegistryConsumer(automation);
        i_forwarder = forwarder;
        i_claSubId = claSubId;
    }

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/
    /// @notice transferAndCall LINK to this address to skip executing 2 txs with approve
    /// @notice the user transferAndCall'ing their LINK to this address will request their KYC status
    /// @dev if the data decodes to a true boolean, Chainlink Automation will be used to execute
    /// compliantly-restricted logic as soon as a request is fulfilled (if the user is compliant)
    function onTokenTransfer(address sender, uint256 amount, bytes calldata data) external {
        if (msg.sender != address(i_link)) revert Compliant__OnlyLinkToken();

        // bool isAutomatedRequest = abi.decode(data, (bool));
        (bool isAutomatedRequest, address user) = abi.decode(data, (bool, address));

        uint256 fees = _handleFeesOnTokenTransfer(isAutomatedRequest);
        if (amount < fees) revert Compliant__InsufficientLinkTransferAmount(amount, fees);

        _requestKycStatus(sender, isAutomatedRequest);
    }

    /// @notice anyone can call this function to request the KYC status of their address
    /// @notice msg.sender must approve address(this) on LINK token contract
    function requestKycStatus(address user) external {
        _handleBasicFees();
        _requestKycStatus(user, false);
    }

    /// @notice requests the KYC status of the msg.sender and then performs compliant-restricted logic
    /// if the msg.sender is eligible
    function requestKycStatusAndPerform() external {
        _handleAutomatedFees();
        _requestKycStatus(msg.sender, true);
    }

    /// @notice example function that can only be called by a compliant user
    function doSomething() external {
        _revertIfNonCompliant(msg.sender);

        // compliant-restricted logic goes here
        s_incrementedValue++;
        emit CompliantCheckPassed();
    }

    /// @dev continuously simulated by Chainlink offchain Automation nodes
    /// @notice upkeepNeeded evaluates to true if the Fulfilled log contains a compliant and pending request address
    /// @param log ILogAutomation.Log
    function checkLog(Log calldata log, bytes memory)
        external
        view
        cannotExecute
        returns (bool upkeepNeeded, bytes memory performData)
    {
        bytes32 eventSignature = keccak256("Fulfilled(bytes32,address,address,uint8,uint40)");

        if (log.source == address(i_everest) && log.topics[0] == eventSignature) {
            bytes32 requestId = log.topics[1];
            address requestedAddress = address(uint160(uint256(log.topics[2])));
            (, IEverestConsumer.Status kycStatus,) = abi.decode(log.data, (address, IEverestConsumer.Status, uint40));

            bool isCompliant;
            if (kycStatus == IEverestConsumer.Status.KYCUser) isCompliant = true;

            if (s_pendingRequests[requestedAddress]) {
                performData = abi.encode(requestId, requestedAddress, isCompliant);
                upkeepNeeded = true;
            }
        }
    }

    /// @notice called by Chainlink Automation forwarder if the user has completed KYC
    /// @dev this function should contain the logic restricted for compliant only users
    /// @param performData encoded bytes contains address of requested user and bool isCompliant
    function performUpkeep(bytes calldata performData) external {
        if (msg.sender != i_forwarder) revert Compliant__OnlyForwarder();
        (bytes32 requestId, address user, bool isCompliant) = abi.decode(performData, (bytes32, address, bool));

        s_pendingRequests[user] = false;

        emit KYCStatusRequestFulfilled(requestId, user, isCompliant);

        if (isCompliant) {
            // compliant-restricted logic goes here
            s_automatedIncrement++;
            emit CompliantCheckPassed();
        }
    }

    /// @dev admin function for withdrawing protocol fees
    function withdrawFees() external onlyOwner {
        uint256 compliantFeesInLink = s_compliantFeesInLink;
        s_compliantFeesInLink = 0;

        i_link.transfer(owner(), compliantFeesInLink);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/
    /// @dev requests the kyc status of the user
    function _requestKycStatus(address user, bool isAutomated) internal {
        if (isAutomated) _setPendingRequest(user);

        i_everest.requestStatus(user);

        bytes32 everestRequestId = i_everest.getLatestSentRequestId();

        s_lastEverestRequestId[user] = everestRequestId;

        emit KYCStatusRequested(everestRequestId, user);
    }

    /// @dev Chainlink Automation will only trigger for a true pending request
    function _setPendingRequest(address user) internal {
        if (s_pendingRequests[user]) revert Compliant__PendingRequestExists(user);
        s_pendingRequests[user] = true;
    }

    /// @dev calculates fees in LINK and handles transfers and approvals
    /// @param isAutomated Whether to include automation fees
    function _handleFees(bool isAutomated) internal {
        uint256 compliantFeeInLink = _calculateCompliantFee();
        uint256 everestFeeInLink = i_everest.oraclePayment();

        s_compliantFeesInLink += compliantFeeInLink;

        uint256 totalFee = compliantFeeInLink + everestFeeInLink;

        if (isAutomated) {
            uint96 automationFeeInLink = i_automation.getMinBalance(i_claSubId);
            totalFee += automationFeeInLink;

            i_link.approve(address(i_automation), automationFeeInLink);
            i_automation.addFunds(i_claSubId, automationFeeInLink);
        }

        i_link.transferFrom(msg.sender, address(this), totalFee);
        i_link.approve(address(i_everest), everestFeeInLink);
    }

    /// @dev calculates fees in LINK and handles transfers and approvals
    /// @param isAutomated Whether to include automation fees
    function _handleFeesOnTokenTransfer(bool isAutomated) internal returns (uint256) {
        uint256 compliantFeeInLink = _calculateCompliantFee();
        uint256 everestFeeInLink = i_everest.oraclePayment();

        s_compliantFeesInLink += compliantFeeInLink;

        uint256 totalFee = compliantFeeInLink + everestFeeInLink;

        if (isAutomated) {
            uint96 automationFeeInLink = i_automation.getMinBalance(i_claSubId);
            totalFee += automationFeeInLink;

            i_link.approve(address(i_automation), automationFeeInLink);
            i_automation.addFunds(i_claSubId, automationFeeInLink);
        }

        i_link.approve(address(i_everest), everestFeeInLink);

        return totalFee;
    }

    /// @dev calculates fees in LINK needed to make KYC request
    function _handleBasicFees() internal {
        _handleFees(false);
    }

    /// @dev calculates fees in LINK needed to make KYC request and automate response
    function _handleAutomatedFees() internal {
        _handleFees(true);
    }

    /// @dev reverts if the user is not compliant
    function _revertIfNonCompliant(address user) internal view {
        if (!_isCompliant(user)) revert Compliant__NonCompliantUser(user);
    }

    /// @dev checks if the user is compliant
    function _isCompliant(address user) internal view returns (bool isCompliant) {
        IEverestConsumer.Request memory kycRequest = i_everest.getLatestFulfilledRequest(user);
        return kycRequest.isKYCUser;
    }

    /// @dev returns the latest LINK/USD price
    function _getLatestPrice() internal view returns (uint256) {
        (, int256 price,,,) = i_priceFeed.latestRoundData();
        return uint256(price);
    }

    /// @dev calculates the fee for this contract
    function _calculateCompliantFee() internal view returns (uint256) {
        return (COMPLIANT_FEE * WAD_PRECISION) / _getLatestPrice();
    }

    /*//////////////////////////////////////////////////////////////
                                 GETTER
    //////////////////////////////////////////////////////////////*/
    /// @param user address of user to query if they have completed KYC
    /// @return isCompliant True if the user has completed KYC
    function getIsCompliant(address user) external view returns (bool isCompliant) {
        return _isCompliant(user);
    }

    function getFee() public view returns (uint256) {
        uint256 compliantFeeInLink = _calculateCompliantFee();
        uint256 everestFeeInLink = i_everest.oraclePayment();

        return compliantFeeInLink + everestFeeInLink;
    }

    function getAutomatedFee() public view returns (uint256) {
        uint96 automationFeeInLink = i_automation.getMinBalance(i_claSubId);

        return getFee() + automationFeeInLink;
    }

    function getEverest() external view returns (IEverestConsumer) {
        return i_everest;
    }

    function getLink() external view returns (LinkTokenInterface) {
        return i_link;
    }

    function getPriceFeed() external view returns (AggregatorV3Interface) {
        return i_priceFeed;
    }

    function getAutomation() external view returns (IAutomationRegistryConsumer) {
        return i_automation;
    }

    function getForwarder() external view returns (address) {
        return i_forwarder;
    }

    function getClaSubId() external view returns (uint256) {
        return i_claSubId;
    }

    function getLastEverestRequestId(address user) external view returns (bytes32) {
        return s_lastEverestRequestId[user];
    }
}
