# Compliant Access Only

## Compliant.sol

This contract contains two practical examples of how a KYC status request can be integrated to restrict functionality to only compliant users.

1. The KYC status of a user can be requested.

   1b. The last fulfilled KYC status request can be read from Everest. This value can then be used to determine if a user can interact with a function (`doSomething()`).

2. Or a KYC status request can be made, with contract functionality immediately executed by Chainlink Log Trigger Automation based on the result.

---

By making the `Compliant` contract an ERC677Receiver, it enables users to request their compliant status in a single `i_link.transferAndCall()` transaction, as opposed to 2 transactions of approving and then requesting.

## Testing

See coverage with `forge coverage --report debug`.

The `cannotExecute` will have to be commented out for some of the tests in `CheckLog.t.sol` to pass.

## User Flow

Users can interact with the Compliant contract in two ways:

1. Call `LINK.transferAndCall()` on the LINK token address, passing the Compliant contract's address, fee amount, and calldata. The calldata should include the address to query and instructions on whether to automate a response to the fulfilled compliance check request. The fee amount to pass can be read from either `Compliant.getFee()` or `Compliant.getFeeWithAutomation()` depending on if the request is intended to use Automation or not. `transferAndCall()` allows the user to request the KYC status in a single transaction. Combining it with the automation option allows the user to request the KYC status and execute subsequent logic based on the immediate result in a single transaction.

2. Call `LINK.approve()` on the LINK token address, passing the Compliant contract's address and fee amount. Then call `Compliant.requestKycStatus()`, passing the address to query and instructions on whether to automate a response to the fulfilled compliance check request.
