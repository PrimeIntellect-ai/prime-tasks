TRO is missing the `TransferOut` receipt
TRO should append a `TransferOut` to the script execution, however it is missing from the current implementation. To resolve this bug, append the `TransferOut` receipt here: https://github.com/FuelLabs/fuel-vm/blob/v0.18.2/[HIDDEN]
