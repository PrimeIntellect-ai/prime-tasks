Multisig test match exitcode instead of abort
From builtin/multisig/multisig_test.go:TestApprove:"fail approve transaction more than once"
`// TODO replace with correct exit code when multisig actor breaks the AbortStateMsg pattern.`

I believe this is related to #434 getting closed out, but something potentially more complicated is going on.  Needs more investigation.

### Additional contract requirements

The `TestApprove` suite in `actors/builtin/multisig/multisig_test.go` must assert the correct
exit codes for the following cases, and the multisig actor must abort with those codes:

- `fail approve transaction more than once`: a signer approving a transaction they have already
  approved must abort with `exitcode.ErrForbidden`.
- `fail approval with bad proposal hash`: approving a transaction with a proposal hash that does
  not match the transaction's computed hash must abort with `exitcode.ErrIllegalArgument`.
