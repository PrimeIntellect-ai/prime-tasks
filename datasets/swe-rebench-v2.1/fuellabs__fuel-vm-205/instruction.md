Remove owner field from MessageInputs
The `owner` field still seems to be queryable via the GTF opcode (see `GTFArgs::InputMessageOwner`). This needs to be update to match the [spec](https://github.com/FuelLabs/fuel-specs/blob/master/specs/vm/instruction_set.md#gtf-get-transaction-fields).

Note: the GTF hex codes have changes for input message data
