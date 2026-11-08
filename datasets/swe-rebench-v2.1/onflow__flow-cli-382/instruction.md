Improve Error Handling when transaction signer does not match authorizer
### Problem

When building and signing a transaction with `flow transactions build` and `flow transactions sign`, if the signer specified in `sign` does not match the authorizer, or any of the signers, specified in `build`, the signing still passes, but the next time you try to do anything with that transaction, such as signing it with another key or sending it, you get this error:
```
panic: runtime error: index out of range [-1]

goroutine 1 [running]:
github.com/onflow/flow-go-sdk.DecodeTransaction({0xc000381600, 0xc000381080, 0x512})
	github.com/onflow/flow-go-sdk@v0.20.1-0.20210623043139-533a95abf071/transaction.go:441 +0x896
github.com/onflow/flow-cli/pkg/flowkit.NewTransactionFromPayload({0xc000366800, 0x512, 0x712})
	github.com/onflow/flow-cli/pkg/flowkit/transaction.go:50 +0x165
github.com/onflow/flow-cli/pkg/flowkit/services.(*Transactions).SendSigned(0xc000218f60, {0xc000366800, 0xc00041e0c0, 0xc0001c7bb8})
	github.com/onflow/flow-cli/pkg/flowkit/services/transactions.go:180 +0x70
github.com/onflow/flow-cli/internal/transactions.sendSigned({0xc0000e5530, 0xc0004abce0, 0x4153323}, {0x51a8d28, 0xc000119ac0}, {{0x0, 0x0}, {0x4ed32c9, 0x4}, {0x0, ...}, ...}, ...)
	github.com/onflow/flow-cli/internal/transactions/send-signed.go:64 +0xbb
github.com/onflow/flow-cli/internal/command.Command.AddToParent.func1(0x5ae1760, {0xc0000e5530, 0x1, 0x3})
	github.com/onflow/flow-cli/internal/command/command.go:116 +0x315
github.com/spf13/cobra.(*Command).execute(0x5ae1760, {0xc000130150, 0x3, 0x3})
	github.com/spf13/cobra@v1.1.3/command.go:856 +0x5f8
github.com/spf13/cobra.(*Command).ExecuteC(0xc000424000)
	github.com/spf13/cobra@v1.1.3/command.go:960 +0x3ad
github.com/spf13/cobra.(*Command).Execute(...)
	github.com/spf13/cobra@v1.1.3/command.go:897
main.main()
	github.com/onflow/flow-cli/cmd/flow/main.go:69 +0x319
```
It would be a lot more helpful if the signing operation failed at the time of signing if the address doesn't match and not later, and the error message should be more descriptive.

### Steps to Reproduce

1. Build a transaction with one or two authorizers specified
2. Sign the transaction with an account that was not specified as an authorizer
3. Try to send the transaction

### Acceptance Criteria

Some sort of better error message when signing or sending. I'm not really sure what makes the most sense.

### Additional contract requirements

- Signing a transaction with an account that is not one of its proposer, payer, or authorizers must return an error (signing or, failing that, sending must fail), rather than producing a transaction that later fails or panics.
- The error for such a rejected signer must explain the reason for the rejection: it must include the address of the account that was refused, so the user can see which signer was not accepted, instead of a generic failure message.
