tpm2: CreateKey should not return a tpmutil.Handle
The TPM2_Create command does not return a handle, but tpm2.CreateKey tries to decode and return one anyway, resulting in a bogus tpmutil.Handle value.

Relatedly, the TPM2_CreateLoaded command doesn't seem available.
