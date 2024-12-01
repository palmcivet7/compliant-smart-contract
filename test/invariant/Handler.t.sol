// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Compliant} from "../../src/Compliant.sol";
import {MockEverestConsumer} from "../mocks/MockEverestConsumer.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

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

    /// @dev track the created revealer addresses
    EnumerableSet.AddressSet internal revealers;
    /// @dev track the created requestedAddresses
    EnumerableSet.AddressSet internal requestedAddresses;

    /// @dev ghost to track direct calls to Compliant implementation
    uint256 public g_directImplementationCalls;
    /// @dev ghost to track direct calls to Compliant implementation that succeeded
    uint256 public g_directCallSuccesses;
    /// @dev ghost to track directs to Compliant implementation that have failed
    uint256 public g_directCallReverts;

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
    constructor(Compliant _compliant, address _compliantProxy, address _deployer, address _link, address _forwarder) {
        compliant = _compliant;
        compliantProxy = _compliantProxy;
        deployer = _deployer;
        link = _link;
        forwarder = _forwarder;
    }

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/
    /// @dev only LINK transferAndCall
    function onTokenTransfer(
        uint256 revealerSeed,
        bool isNewRevealer,
        uint256 requestedAddressSeed,
        bool isNewRequestedAddress,
        bool isCompliant,
        bool isAutomation,
        bytes calldata compliantCalldata
    ) public {
        /// @dev create or get revealer and requestedAddress, then set/fuzz requestedAddress Everest status
        (address revealer, address requestedAddress) =
            _setUpRequest(revealerSeed, isNewRevealer, requestedAddressSeed, isNewRequestedAddress, isCompliant);

        /// @dev deal link to revealer
        uint256 amount = _dealLink(revealer, isAutomation);

        /// @dev store compliantCalldata in ghost mapping
        if (isAutomation && compliantCalldata.length > 0) {
            g_requestedAddressToCalldata[requestedAddress] = compliantCalldata;
        }

        /// @dev set request to pending
        if (isAutomation) {
            g_pendingRequests[requestedAddress] = true;
        }

        /// @dev create calldata for transferAndCall request
        bytes memory data = abi.encode(requestedAddress, isAutomation, compliantCalldata);

        /// @dev request KYC status with transferAndCall
        vm.startPrank(revealer);
        compliant.getLink().transferAndCall(address(compliantProxy), amount, data);
        vm.stopPrank();

        /// @notice the Fulfilled event that gets emitted here SHOULD trigger Chainlink Automation
        /// This is not happening, even though we simulated registering and enabling all log triggers on our mainnet fork,
        /// because Chainlink's offchain automation nodes are separate from our environment.

        if (g_pendingRequests[requestedAddress]) {
            performUpkeep(requestedAddress, isCompliant);
        }
    }

    function requestKycStatus(
        uint256 revealerSeed,
        bool isNewRevealer,
        uint256 requestedAddressSeed,
        bool isNewRequestedAddress,
        bool isCompliant,
        bool isAutomation,
        bytes calldata compliantCalldata
    ) public {
        /// @dev create or get revealer and requestedAddress, then set/fuzz requestedAddress Everest status
        (address revealer, address requestedAddress) =
            _setUpRequest(revealerSeed, isNewRevealer, requestedAddressSeed, isNewRequestedAddress, isCompliant);

        /// @dev deal link to revealer
        uint256 amount = _dealLink(revealer, isAutomation);

        /// @dev approve compliantProxy to spend link
        vm.startPrank(revealer);
        compliant.getLink().approve(address(compliantProxy), amount);

        /// @dev store compliantCalldata in ghost mapping
        if (isAutomation && compliantCalldata.length > 0) {
            g_requestedAddressToCalldata[requestedAddress] = compliantCalldata;
        }

        /// @dev requestKycStatus
        (bool success,) = address(compliantProxy).call(
            abi.encodeWithSignature(
                "requestKycStatus(address,bool,bytes)", requestedAddress, isAutomation, compliantCalldata
            )
        );
        require(success, "delegate call in handler to requestKycStatus() failed");

        vm.stopPrank();

        if (isAutomation) {
            performUpkeep(requestedAddress, isCompliant);
        }
    }

    /// @dev onlyCompliant
    function doSomething(uint256 requestedAddressSeed, bool isNewRevealer) public {
        address user = _createOrGetRequestedAddress(requestedAddressSeed, isNewRevealer);
        if (g_requestedAddressToStatus[user]) {
            vm.prank(user);
            (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("doSomething()"));
            require(success, "delegate call in handler to doSomething() failed");
        }
    }

    /// @dev cannotExecute
    function checkLog() public {}

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
    function withdrawFees(
        uint256 revealerSeed,
        bool isNewRevealer,
        uint256 revealeeSeed,
        bool isNewRevealee,
        bool isCompliant,
        bool isAutomation,
        bytes calldata compliantCalldata
    ) public {
        if (g_compliantFeesInLink == 0) {
            requestKycStatus(
                revealerSeed, isNewRevealer, revealeeSeed, isNewRevealee, isCompliant, isAutomation, compliantCalldata
            );
        } else {
            vm.prank(compliant.owner());
            compliant.withdrawFees();
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
        address revealer = _seedToAddress(addressSeed++);
        address requestedAddress = _seedToAddress(addressSeed);

        /// @dev make direct call to one of external functions
        uint256 choice = divisor % 4;
        if (choice == 0) {
            directOnTokenTransfer(revealer, requestedAddress, isAutomation, compliantCalldata);
        } else if (choice == 1) {
            directRequestKycStatus(revealer, requestedAddress, isAutomation, compliantCalldata);
        } else if (choice == 2) {
            directDoSomething();
        } else if (choice == 3) {
            directWithdrawFees();
        } else {
            revert("Invalid choice");
        }
    }

    function directOnTokenTransfer(
        address revealer,
        address requestedAddress,
        bool isAutomation,
        bytes memory compliantCalldata
    ) public {
        uint256 amount;
        if (isAutomation) amount = compliant.getFeeWithAutomation();
        else amount = compliant.getFee();
        deal(link, revealer, amount);

        bytes memory data = abi.encode(requestedAddress, isAutomation, compliantCalldata);

        vm.prank(revealer);
        try LinkTokenInterface(link).transferAndCall(address(compliant), amount, data) {
            g_directCallSuccesses++;
        } catch (bytes memory error) {
            _handleOnlyProxyError(error);
        }
    }

    function directRequestKycStatus(
        address revealer,
        address requestedAddress,
        bool isAutomation,
        bytes memory compliantCalldata
    ) public {
        uint256 amount;
        if (isAutomation) amount = compliant.getFeeWithAutomation();
        else amount = compliant.getFee();
        deal(link, revealer, amount);

        vm.prank(revealer);
        try compliant.requestKycStatus(requestedAddress, isAutomation, compliantCalldata) {
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
    function _performUpkeep() internal {}

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
    /// @dev convert a seed to an address
    function _seedToAddress(uint256 addressSeed) internal pure returns (address) {
        return address(uint160(bound(addressSeed, 1, type(uint160).max)));
    }

    /// @dev create a revealer address for calling requestKycStatus or onTokenTransfer
    function _createOrGetRevealer(uint256 addressSeed, bool createRevealer) internal returns (address) {
        if (revealers.length() == 0 || createRevealer) {
            address revealer = _seedToAddress(addressSeed);
            revealers.add(revealer);

            return revealer;
        } else if (!createRevealer) {
            return _indexToRevealerAddress(addressSeed);
        }
    }

    /// @dev convert an index to an existing revealer address
    function _indexToRevealerAddress(uint256 addressIndex) internal view returns (address) {
        return revealers.at(bound(addressIndex, 0, revealers.length() - 1));
    }

    /// @dev create a revealee address for calling requestKycStatus or onTokenTransfer
    function _createOrGetRequestedAddress(uint256 addressSeed, bool createRequestedAddress)
        internal
        returns (address)
    {
        if (requestedAddresses.length() == 0 || createRequestedAddress) {
            address revealee = _seedToAddress(addressSeed);
            requestedAddresses.add(revealee);

            return revealee;
        } else if (!createRequestedAddress) {
            return _indexToRequestedAddresses(addressSeed);
        }
    }

    /// @dev convert an index to an existing revealee address
    function _indexToRequestedAddresses(uint256 addressIndex) internal view returns (address) {
        return requestedAddresses.at(bound(addressIndex, 0, requestedAddresses.length() - 1));
    }

    /// @dev set/fuzz the everest status of a requestedAddress
    function _setEverestStatus(address revealer, address requestedAddress, bool isCompliant) internal {
        MockEverestConsumer(address(compliant.getEverest())).setLatestFulfilledRequest(
            false, isCompliant, isCompliant, revealer, requestedAddress, uint40(block.timestamp)
        );

        g_requestedAddressToStatus[requestedAddress] = isCompliant;
    }

    /// @dev deal link to revealer to pay for funds and return amount
    function _dealLink(address receiver, bool isAutomation) internal returns (uint256) {
        uint256 amount;
        if (isAutomation) amount = compliant.getFeeWithAutomation();
        else amount = compliant.getFee();

        deal(link, receiver, amount);

        return amount;
    }

    /// @dev set up a new request and get the revealer and requestedAddress
    function _setUpRequest(
        uint256 revealerSeed,
        bool isNewRevealer,
        uint256 requestedAddressSeed,
        bool isNewRequestedAddress,
        bool isCompliant
    ) internal returns (address, address) {
        /// @dev create or get a revealer
        address revealer = _createOrGetRevealer(revealerSeed, isNewRevealer);
        /// @dev create or get a requestedAddress
        address requestedAddress = _createOrGetRequestedAddress(requestedAddressSeed, isNewRequestedAddress);

        // /// @dev if requestedAddress is pending, get a new one
        // if (g_pendingRequests[requestedAddress]) {
        //     requestedAddress = _createOrGetRequestedAddress(requestedAddressSeed++, true);
        // }

        /// @dev set/fuzz the everest status of the requestedAddress
        _setEverestStatus(revealer, requestedAddress, isCompliant);

        return (revealer, requestedAddress);
    }
}
