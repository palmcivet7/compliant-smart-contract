# Compliant Smart Contract

This project demonstrates a compliant smart contract. The `Compliant` contract be can interacted with to request the KYC status of an address and automatically execute logic based on the result.

## Table of Contents

- [Compliant Smart Contract](#compliant-smart-contract)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [How does the compliance work?](#how-does-the-compliance-work)
  - [User Flow](#user-flow)
  - [Compliant.sol](#compliantsol)
  - [Testing](#testing)
  - [Formal Verification](#formal-verification)
  - [Deployment](#deployment)
  - [Additional Comments](#additional-comments)

## Overview

Contract level compliance removes the risk of non-compliance at the lowest level of agreement execution.

## How does the compliance work?

Requests for the KYC status of an address are made through the Chainlink network to a highly regulated provider of private, contract level and sybil resistant user data.

The request is for whether the address being queried has been sybil resistantly linked to someone who has completed KYC with that regulated entity or not.

Compliant restricted logic can only be executed on behalf of users who meet this criteria.

## User Flow

Users can interact with the Compliant contract to request the KYC status of an address in two ways:

1. Call `LINK.transferAndCall()` on the LINK token address, passing the Compliant contract's address, fee amount, and calldata. The calldata should include the address to query, instructions on whether to automate a response to the fulfilled compliance check request, and arbitrary data to pass to compliant restricted logic if automated execution is enabled and user is compliant. The fee amount to pass can be read from either `Compliant.getFee()` or `Compliant.getFeeWithAutomation()` depending on if the request is intended to use Automation or not. `transferAndCall()` allows the user to request the KYC status in a single transaction. Combining it with the automation option allows the user to request the KYC status and execute subsequent logic based on the immediate result in a single transaction.

By making the `Compliant` contract an `ERC677Receiver`, it enables users to request their compliant status in a single `i_link.transferAndCall()` transaction, as opposed to 2 transactions of approving and then requesting.

2. Call `LINK.approve()` on the LINK token address, passing the Compliant contract's address and fee amount. Then call `Compliant.requestKycStatus()`, passing the address to query and instructions on whether to automate a response to the fulfilled compliance check request, and arbitrary data to pass to compliant restricted logic if automated execution is enabled and user is compliant.

## Compliant.sol

This contract contains two practical examples of how a KYC status request can be integrated to restrict functionality to only compliant users.

1. The KYC status of a user can be requested.

   1b. The last fulfilled KYC status request can be read from Everest. This value can then be used to determine if a user can interact with a function (`doSomething()`). This functionality could also be used without having first made a request, relying on the latest fulfilled request somebody else has made about an address.

2. Or a KYC status request can be made, with contract functionality immediately executed by Chainlink Log Trigger Automation based on the result.

## Testing

See coverage with `forge coverage` and `forge coverage --report debug`.

The `cannotExecute` modifier on `checkLog()` will have to be commented out for some of the tests in `CheckLog.t.sol` to pass. This will also require the `test_compliant_checkLog_revertsWhen_called` test to be commented out too.

For unit tests run:

```
forge test --mt test_compliant
```

For invariant tests run:

```
forge test --mt invariant
```

## Formal Verification

This project uses [Certora](https://docs.certora.com/en/latest/) for formal verification.

To run the specification, first export your Certora prover key, and then run the configuration file:

```
export CERTORAKEY= <YOUR_KEY_HERE>
certoraRun ./certora/conf/Compliant.conf
```

---

## Deployment

This project uses a `TransparentUpgradeableProxy` (`CompliantProxy`) to store Chainlink Automation `forwarder` and `upkeepId` as immutable, saving gas for the end user. These are the deployment steps to ensure this functionality and immutability of the `Compliant` contract:

- deploy `InitialImplementation`, an essentially blank contract that implements the `ILogAutomation` interface to make it compatible with registering for Chainlink Automation
- deploy `CompliantProxy`, pointing at the `InitialImplementation`
- register `CompliantProxy` with Chainlink Automation
- deploy `Compliant` with immutable `forwarder` and `upkeepId`
- upgrade `CompliantProxy` to point at `Compliant`
- renounceOwnership of CompliantProxy's `ProxyAdmin` Admin, ensuring the implementation cannot be changed again

---

A `pendingRequest` in the context of this system refers to requests that are pending automation. This name needs to be reviewed for clarity/confusion reasons as requests that are not pending automation are not set to true in this mapping.

---

All user facing functions that change state can only be called via proxy.

---

## Additional Comments

This project uses a [forked version of the EverestConsumer](https://github.com/palmcivet7/everest-chainlink-consumer) with updated Chainlink function names, gas optimizations and mislabelling fix in the `IEverestConsumer` interface that would've returned the incorrect compliant status.
