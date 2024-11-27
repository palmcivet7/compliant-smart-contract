// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {ILogAutomation, Log} from "@chainlink/contracts/src/v0.8/automation/interfaces/ILogAutomation.sol";
import {AutomationBase} from "@chainlink/contracts/src/v0.8/automation/AutomationBase.sol";
import {IAutomationRegistryConsumer} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/IAutomationRegistryConsumer.sol";
import {IAutomationForwarder} from "@chainlink/contracts/src/v0.8/automation/interfaces/IAutomationForwarder.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC677Receiver} from "@chainlink/contracts/src/v0.8/shared/interfaces/IERC677Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice A template contract for requesting and getting the KYC compliant status of an address.
contract Compliant is ILogAutomation, AutomationBase, Ownable, IERC677Receiver {
    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    using SafeERC20 for LinkTokenInterface;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error Compliant__OnlyProxy();
    error Compliant__OnlyLinkToken();
    error Compliant__InsufficientLinkTransferAmount(uint256 insufficientAmount, uint256 requiredAmount);
    error Compliant__NonCompliantUser(address nonCompliantUser);
    error Compliant__PendingRequestExists(address pendingRequestedAddress);
    error Compliant__OnlyForwarder();
    error Compliant__RequestNotMadeByThisContract();

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @param compliantCalldata arbitrary data to pass to compliantly-restricted function if applicable
    /// @param isPending if this is true and a Fulfilled event is emitted by Everest, Chainlink Automation will perform
    struct PendingRequest {
        bytes compliantCalldata;
        bool isPending;
    }

    /// @dev 18 token decimals
    uint256 internal constant WAD_PRECISION = 1e18;
    /// @dev $0.50 to 8 decimals because price feeds have 8 decimals
    /// @notice this value could be something different or even configurable
    /// this could be the max - review this
    uint256 internal constant COMPLIANT_FEE = 5e7; // 50_000_000

    /// @dev Everest Chainlink Consumer
    IEverestConsumer internal immutable i_everest;
    /// @dev LINK token contract
    LinkTokenInterface internal immutable i_link;
    /// @dev Chainlink PriceFeed for LINK/USD
    AggregatorV3Interface internal immutable i_linkUsdFeed;
    /// @dev Chainlink Automation forwarder
    IAutomationForwarder internal immutable i_forwarder;
    /// @dev Chainlink Automation upkeep/subscription ID
    uint256 internal immutable i_upkeepId;
    /// @dev Compliant Proxy that all calls should go through
    address internal immutable i_proxy;

    /// @dev tracks the accumulated fees for this contract in LINK
    uint256 internal s_compliantFeesInLink;
    /// @dev maps a user to a PendingRequest struct if the request requires Automation
    mapping(address user => PendingRequest) internal s_pendingRequests;

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
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /// @dev prevent direct calls made to this contract
    modifier onlyProxy() {
        if (address(this) != i_proxy) revert Compliant__OnlyProxy();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @param everest Everest Chainlink consumer
    /// @param link LINK token
    /// @param linkUsdFeed LINK/USD Chainlink PriceFeed
    /// @param forwarder Chainlink Automation forwarder
    /// @param upkeepId Chainlink Automation upkeep/subscription ID
    /// @param proxy Compliant Proxy address
    constructor(address everest, address link, address linkUsdFeed, address forwarder, uint256 upkeepId, address proxy)
        Ownable(msg.sender)
    {
        i_everest = IEverestConsumer(everest);
        i_link = LinkTokenInterface(link);
        i_linkUsdFeed = AggregatorV3Interface(linkUsdFeed);
        i_forwarder = IAutomationForwarder(forwarder);
        i_upkeepId = upkeepId;
        i_proxy = proxy;
    }

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/
    /// @notice transferAndCall LINK to this address to skip executing 2 txs with approve and requestKycStatus
    /// @param amount fee to pay for the request get it from getFee() or getFeeWithAutomation()
    /// @param data encoded data should contain the user address to request the kyc status of, a boolean
    /// indicating whether automation should be used to subsequently execute logic based on the immediate result,
    /// and arbitrary data to be passed to compliant restricted logic
    function onTokenTransfer(address, /*sender */ uint256 amount, bytes calldata data) external onlyProxy {
        if (msg.sender != address(i_link)) revert Compliant__OnlyLinkToken();

        (address user, bool isAutomatedRequest, bytes memory compliantCalldata) =
            abi.decode(data, (address, bool, bytes));

        uint256 fees = _handleFees(isAutomatedRequest, true);
        if (amount < fees) revert Compliant__InsufficientLinkTransferAmount(amount, fees);

        _requestKycStatus(user, isAutomatedRequest, compliantCalldata);
    }

    /// @notice anyone can call this function to request the KYC status of their address
    /// @notice msg.sender must approve address(this) on LINK token contract
    /// @param user address to request kyc status of
    /// @param isAutomated true if using automation to execute logic based on fulfilled request
    /// @param compliantCalldata arbitrary data to pass to compliantly restricted logic based on fulfilled request
    function requestKycStatus(address user, bool isAutomated, bytes calldata compliantCalldata)
        external
        onlyProxy
        returns (uint256)
    {
        uint256 fee = _handleFees(isAutomated, false);
        _requestKycStatus(user, isAutomated, compliantCalldata);
        return fee;
    }

    /// @notice example function that can only be called by a compliant user
    function doSomething() external onlyProxy {
        _revertIfNonCompliant(msg.sender);

        // compliant-restricted logic goes here
        s_incrementedValue++;
        emit CompliantCheckPassed();
    }

    /// @dev continuously simulated by Chainlink offchain Automation nodes
    /// @notice upkeepNeeded evaluates to true if the Fulfilled log contains a pending requested address
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

            /// @dev revert if request wasn't made by this contract
            address revealer = address(uint160(uint256(log.topics[2])));
            if (revealer != address(this)) revert Compliant__RequestNotMadeByThisContract();

            (address requestedAddress, IEverestConsumer.Status kycStatus,) =
                abi.decode(log.data, (address, IEverestConsumer.Status, uint40));

            bool isCompliant;
            if (kycStatus == IEverestConsumer.Status.KYCUser) isCompliant = true;

            if (s_pendingRequests[requestedAddress].isPending) {
                performData = abi.encode(requestId, requestedAddress, isCompliant);
                upkeepNeeded = true;
            }
        }
    }

    /// @notice called by Chainlink Automation forwarder if the user has completed KYC
    /// @dev this function should contain the logic restricted for compliant only users
    /// @param performData encoded bytes contains bytes32 requestId, address of requested user and bool isCompliant
    function performUpkeep(bytes calldata performData) external onlyProxy {
        if (msg.sender != address(i_forwarder)) revert Compliant__OnlyForwarder();
        (bytes32 requestId, address user, bool isCompliant) = abi.decode(performData, (bytes32, address, bool));

        s_pendingRequests[user].isPending = false;

        bytes memory data = s_pendingRequests[user].compliantCalldata;
        /// @dev reset compliantCalldata mapped to user
        if (data.length > 0) {
            s_pendingRequests[user].compliantCalldata = "";
        }

        emit KYCStatusRequestFulfilled(requestId, user, isCompliant);

        if (isCompliant) {
            // compliant-restricted logic goes here
            _executeCompliantLogic(user, data);

            s_automatedIncrement++;
            emit CompliantCheckPassed();
        }
    }

    /// @dev admin function for withdrawing protocol fees
    function withdrawFees() external onlyOwner onlyProxy {
        uint256 compliantFeesInLink = s_compliantFeesInLink;
        s_compliantFeesInLink = 0;

        i_link.transfer(owner(), compliantFeesInLink);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/
    /// @dev inherit and implement this
    function _executeCompliantLogic(address user, bytes memory data) internal virtual {}

    /// @dev requests the kyc status of the user
    function _requestKycStatus(address user, bool isAutomated, bytes memory compliantCalldata) internal {
        if (isAutomated) _setPendingRequest(user, compliantCalldata);

        i_everest.requestStatus(user);

        bytes32 everestRequestId = i_everest.getLatestSentRequestId();

        emit KYCStatusRequested(everestRequestId, user);
    }

    /// @dev Chainlink Automation will only trigger for a true pending request
    function _setPendingRequest(address user, bytes memory compliantCalldata) internal {
        if (s_pendingRequests[user].isPending) revert Compliant__PendingRequestExists(user);
        s_pendingRequests[user].isPending = true;

        if (compliantCalldata.length > 0) {
            s_pendingRequests[user].compliantCalldata = compliantCalldata;
        }
    }

    /// @dev calculates fees in LINK and handles approvals
    /// @param isAutomated Whether to include automation fees
    /// @param isOnTokenTransfer if the tx was initiated by erc677 onTokenTransfer, we don't need to transferFrom(msg.sender)
    function _handleFees(bool isAutomated, bool isOnTokenTransfer) internal returns (uint256) {
        uint256 compliantFeeInLink = _calculateCompliantFee();
        uint256 everestFeeInLink = i_everest.oraclePayment();

        s_compliantFeesInLink += compliantFeeInLink;

        uint256 totalFee = compliantFeeInLink + everestFeeInLink;

        IAutomationRegistryConsumer registry = i_forwarder.getRegistry();

        uint96 automationFeeInLink = registry.getMinBalance(i_upkeepId);

        if (isAutomated) {
            totalFee += automationFeeInLink;

            i_link.approve(address(registry), automationFeeInLink);
        }

        if (!isOnTokenTransfer) {
            i_link.transferFrom(msg.sender, address(this), totalFee);
        }

        if (isAutomated) {
            registry.addFunds(i_upkeepId, automationFeeInLink);
        }

        i_link.approve(address(i_everest), everestFeeInLink);

        return totalFee;
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
        (, int256 price,,,) = i_linkUsdFeed.latestRoundData();
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

    /// @notice returns the fee for a standard KYC request
    function getFee() public view returns (uint256) {
        uint256 compliantFeeInLink = _calculateCompliantFee();
        uint256 everestFeeInLink = i_everest.oraclePayment();

        return compliantFeeInLink + everestFeeInLink;
    }

    /// @notice returns the fee for a KYC request with subsequent automated logic
    function getFeeWithAutomation() external view returns (uint256) {
        IAutomationRegistryConsumer registry = i_forwarder.getRegistry();
        uint96 automationFeeInLink = registry.getMinBalance(i_upkeepId);

        return getFee() + automationFeeInLink;
    }

    /// @notice returns the protocol fees available to withdraw by admin
    function getCompliantFeesToWithdraw() external view returns (uint256) {
        return s_compliantFeesInLink;
    }

    function getEverest() external view returns (IEverestConsumer) {
        return i_everest;
    }

    function getLink() external view returns (LinkTokenInterface) {
        return i_link;
    }

    function getLinkUsdFeed() external view returns (AggregatorV3Interface) {
        return i_linkUsdFeed;
    }

    function getForwarder() external view returns (IAutomationForwarder) {
        return i_forwarder;
    }

    function getUpkeepId() external view returns (uint256) {
        return i_upkeepId;
    }

    function getPendingRequest(address user) external view returns (PendingRequest memory) {
        return s_pendingRequests[user];
    }

    /// @notice getter for example value
    function getIncrementedValue() external view returns (uint256) {
        return s_incrementedValue;
    }

    /// @notice getter for example value
    function getAutomatedIncrement() external view returns (uint256) {
        return s_automatedIncrement;
    }
}
