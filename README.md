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
