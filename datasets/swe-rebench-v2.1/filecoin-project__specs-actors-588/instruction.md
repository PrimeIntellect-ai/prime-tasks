Multisig:  [HIDDEN]
In functions like `RemoveSigner` and `SwapSigner`,  when we determine if the signer passed in the params is the same as one of the signers we have on the state, we don't account for the fact that they could have different address types.

### Additional contract requirements

- In `RemoveSigner` and `SwapSigner`, a passed signer address and a stored signer address that identify the same actor must be treated as the same signer, even if their address types differ.
