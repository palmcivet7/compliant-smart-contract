// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Compliant} from "../../src/Compliant.sol";
import {MockEverestConsumer} from "../mocks/MockEverestConsumer.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";

contract Handler is Test {
    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @dev compliant contract being handled
    Compliant public compliant;
    /// @dev compliant proxy being handled
    address public compliantProxy;
    /// @dev deployer
    address public deployer;
    /// @dev LINK token
    address public link;
    /// @dev Chainlink Automation forwarder
    address public forwarder;
    /// @dev Everest Chainlink Consumer
    address public everest;
    /// @dev ProxyAdmin contract
    address public proxyAdmin;

    /// @dev track the users in the system (requestedAddresses)
    EnumerableSet.AddressSet internal users;

    /// @dev ghost to track direct calls to Compliant implementation
    uint256 public g_directImplementationCalls;
    /// @dev ghost to track direct calls to Compliant implementation that succeeded
    uint256 public g_directCallSuccesses;
    /// @dev ghost to track direct calls to Compliant implementation that have failed
    uint256 public g_directCallReverts;

    /// @dev ghost to track total Compliant protocol fees that have been paid by users
    uint256 public g_totalFeesEarned;
    /// @dev ghost to track total fees that have been withdrawn
    uint256 public g_totalFeesWithdrawn;

    /// @dev ghost to track withdrawable admin fees
    uint256 public g_compliantFeesInLink;
    /// @dev ghost to track requestedAddresses to compliant status
    mapping(address requestedAddress => bool isCompliant) public g_requestedAddressToStatus;
    /// @dev ghost to track requestedAddresses to compliant calldata
    mapping(address requestedAddress => bytes compliantCalldata) public g_requestedAddressToCalldata;
    /// @dev ghost to track pending requests
    mapping(address requestedAddress => bool isPending) public g_pendingRequests;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        Compliant _compliant,
        address _compliantProxy,
        address _deployer,
        address _link,
        address _forwarder,
        address _everest,
        address _proxyAdmin
    ) {
        compliant = _compliant;
        compliantProxy = _compliantProxy;
        deployer = _deployer;
        link = _link;
        forwarder = _forwarder;
        everest = _everest;
        proxyAdmin = _proxyAdmin;
    }

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/
    /// @dev only LINK transferAndCall
    function onTokenTransfer(uint256 addressSeed, bool isCompliant, bool isAutomation, bytes calldata compliantCalldata)
        public
    {
        /// @dev create a user
        address user = _seedToAddress(addressSeed);
        require(user != proxyAdmin && user != compliantProxy, "Invalid address used.");
        /// @dev set the Everest status for the request (we pass user twice because they are revealing themselves)
        _setEverestStatus(user, isCompliant);

        /// @dev deal link to user
        uint256 amount = _dealLink(user, isAutomation);

        /// @dev store compliantCalldata in ghost mapping
        if (isAutomation && compliantCalldata.length > 0) {
            g_requestedAddressToCalldata[user] = compliantCalldata;
        }

        /// @dev set request to pending
        if (isAutomation) {
            g_pendingRequests[user] = true;
        }

        /// @dev update totalFeesEarned ghost
        g_totalFeesEarned += compliant.getFee() - IEverestConsumer(everest).oraclePayment();

        /// @dev create calldata for transferAndCall request
        bytes memory data = abi.encode(user, isAutomation, compliantCalldata);

        /// @dev request KYC status with transferAndCall
        vm.startPrank(user);
        compliant.getLink().transferAndCall(address(compliantProxy), amount, data);

        users.add(user);
        vm.stopPrank();

        /// @notice the Fulfilled event that gets emitted here SHOULD trigger Chainlink Automation
        /// This is not happening, even though we simulated registering and enabling all log triggers on our mainnet fork,
        /// because Chainlink's offchain automation nodes are separate from our environment.

        if (g_pendingRequests[user]) {
            performUpkeep(user, isCompliant);
        }
    }

    function requestKycStatus(
        uint256 addressSeed,
        bool isCompliant,
        bool isAutomation,
        bytes calldata compliantCalldata
    ) public {
        /// @dev create a user
        address user = _seedToAddress(addressSeed);
        require(user != proxyAdmin && user != compliantProxy, "Invalid address used.");
        /// @dev set the Everest status for the request (we pass user twice because they are revealing themselves)
        _setEverestStatus(user, isCompliant);

        /// @dev deal link to user
        uint256 amount = _dealLink(user, isAutomation);

        /// @dev approve compliantProxy to spend link
        vm.startPrank(user);
        compliant.getLink().approve(address(compliantProxy), amount);

        /// @dev store compliantCalldata in ghost mapping
        if (isAutomation && compliantCalldata.length > 0) {
            g_requestedAddressToCalldata[user] = compliantCalldata;
        }

        g_totalFeesEarned += compliant.getFee() - IEverestConsumer(everest).oraclePayment();

        /// @dev requestKycStatus
        (bool success,) = address(compliantProxy).call(
            abi.encodeWithSignature("requestKycStatus(address,bool,bytes)", user, isAutomation, compliantCalldata)
        );
        require(success, "delegate call in handler to requestKycStatus() failed");

        users.add(user);
        vm.stopPrank();

        if (isAutomation) {
            performUpkeep(user, isCompliant);
        }
    }

    /// @dev onlyCompliant
    function doSomething(uint256 addressSeed) public {
        address user = _createOrGetUser(addressSeed);
        require(user != proxyAdmin && user != compliantProxy, "Invalid address used.");

        if (g_requestedAddressToStatus[user]) {
            vm.prank(user);
            (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("doSomething()"));
            require(success, "delegate call in handler to doSomething() failed");

            // update some ghost
        }
    }

    /// @dev onlyForwarder
    function performUpkeep(address requestedAddress, bool isCompliant) public {
        bytes32 requestId = bytes32(uint256(uint160(requestedAddress)));
        bytes memory performData = abi.encode(requestId, requestedAddress, isCompliant);

        vm.prank(forwarder);
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("performUpkeep(bytes)", performData));
        require(success, "delegate call in handler to performUpkeep() failed");

        g_pendingRequests[requestedAddress] = false;
    }

    /// @dev onlyOwner
    function withdrawFees(uint256 addressSeed, bool isCompliant, bool isAutomation, bytes calldata compliantCalldata)
        public
    {
        if (g_compliantFeesInLink == 0) {
            requestKycStatus(addressSeed, isCompliant, isAutomation, compliantCalldata);
        } else {
            /// @dev getCompliantFeesToWithdraw and add it to ghost tracker
            (, bytes memory retData) =
                address(compliantProxy).call(abi.encodeWithSignature("getCompliantFeesToWithdraw()"));
            uint256 fees = abi.decode(retData, (uint256));
            g_totalFeesWithdrawn += fees;

            vm.prank(compliant.owner());
            (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("withdrawFees()"));
            require(success, "delegate call in handler to withdrawFees() failed");
            g_compliantFeesInLink = 0;
        }
    }

    /// @dev onlyProxy
    // @review readability/modularity can be improved here
    function externalImplementationCalls(
        uint256 divisor,
        uint256 addressSeed,
        bool isAutomation,
        bytes memory compliantCalldata
    ) public {
        /// @dev increment ghost
        g_directImplementationCalls++;

        /// @dev get revealer and requestedAddress
        addressSeed = bound(addressSeed, 1, type(uint256).max - 1);
        address user = _seedToAddress(addressSeed);

        /// @dev make direct call to one of external functions
        uint256 choice = divisor % 4;
        if (choice == 0) {
            directOnTokenTransfer(user, isAutomation, compliantCalldata);
        } else if (choice == 1) {
            directRequestKycStatus(user, isAutomation, compliantCalldata);
        } else if (choice == 2) {
            directDoSomething();
        } else if (choice == 3) {
            directWithdrawFees();
        } else {
            revert("Invalid choice");
        }
    }

    function directOnTokenTransfer(address user, bool isAutomation, bytes memory compliantCalldata) public {
        uint256 amount;
        if (isAutomation) amount = compliant.getFeeWithAutomation();
        else amount = compliant.getFee();
        deal(link, user, amount);

        bytes memory data = abi.encode(user, isAutomation, compliantCalldata);

        vm.prank(user);
        try LinkTokenInterface(link).transferAndCall(address(compliant), amount, data) {
            g_directCallSuccesses++;
        } catch (bytes memory error) {
            _handleOnlyProxyError(error);
        }
    }

    function directRequestKycStatus(address user, bool isAutomation, bytes memory compliantCalldata) public {
        uint256 amount;
        if (isAutomation) amount = compliant.getFeeWithAutomation();
        else amount = compliant.getFee();
        deal(link, user, amount);

        vm.prank(user);
        try compliant.requestKycStatus(user, isAutomation, compliantCalldata) {
            g_directCallSuccesses++;
        } catch (bytes memory error) {
            _handleOnlyProxyError(error);
        }
    }

    function directDoSomething() public {
        try compliant.doSomething() {
            g_directCallSuccesses++;
        } catch (bytes memory error) {
            _handleOnlyProxyError(error);
        }
    }

    function directWithdrawFees() public {
        try compliant.withdrawFees() {
            g_directCallSuccesses++;
        } catch (bytes memory error) {
            _handleOnlyProxyError(error);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/
    function _handleOnlyProxyError(bytes memory error) internal {
        g_directCallReverts++;

        bytes4 selector;
        assembly {
            selector := mload(add(error, 32))
        }
        assertEq(selector, bytes4(keccak256("Compliant__OnlyProxy()")));
    }

    /*//////////////////////////////////////////////////////////////
                                UTILITY
    //////////////////////////////////////////////////////////////*/
    /// @dev helper function for looping through users in the system
    function forEachUser(function(address) external func) external {
        for (uint256 i; i < users.length(); ++i) {
            func(users.at(i));
        }
    }

    /// @dev convert a seed to an address
    function _seedToAddress(uint256 addressSeed) internal view returns (address seedAddress) {
        uint160 boundInt = uint160(bound(addressSeed, 1, type(uint160).max));
        seedAddress = address(boundInt);
        if (seedAddress == compliantProxy) {
            addressSeed++;
            boundInt = uint160(bound(addressSeed, 1, type(uint160).max));
            seedAddress = address(boundInt);
            if (seedAddress == proxyAdmin) {
                addressSeed++;
                boundInt = uint160(bound(addressSeed, 1, type(uint160).max));
                seedAddress = address(boundInt);
            }
        }
        vm.assume(seedAddress != proxyAdmin);
        vm.assume(seedAddress != compliantProxy);
        return seedAddress;
    }

    /// @dev create a user address for calling and passing to requestKycStatus or onTokenTransfer
    function _createOrGetUser(uint256 addressSeed) internal returns (address user) {
        if (users.length() == 0) {
            user = _seedToAddress(addressSeed);
            users.add(user);

            return user;
        } else {
            user = _indexToUser(addressSeed);

            return user;
        }
    }

    /// @dev convert an index to an existing user
    function _indexToUser(uint256 addressIndex) internal view returns (address) {
        return users.at(bound(addressIndex, 0, users.length() - 1));
    }

    /// @dev set/fuzz the everest status of a requestedAddress
    function _setEverestStatus(address user, bool isCompliant) internal {
        MockEverestConsumer(address(compliant.getEverest())).setLatestFulfilledRequest(
            false, isCompliant, isCompliant, address(compliantProxy), user, uint40(block.timestamp)
        );

        g_requestedAddressToStatus[user] = isCompliant;
    }

    /// @dev deal link to revealer to pay for funds and return amount
    function _dealLink(address receiver, bool isAutomation) internal returns (uint256) {
        uint256 amount;
        if (isAutomation) amount = compliant.getFeeWithAutomation();
        else amount = compliant.getFee();

        deal(link, receiver, amount);

        return amount;
    }
}
