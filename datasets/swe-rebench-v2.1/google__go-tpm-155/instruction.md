Should unpack of U16/U32Bytes validate a max size?
Malicious attacker-controlled input could make its way to `tpmutil.Unpack()` of `U32Bytes` or `U16Bytes`. For instance, calling `tpm.UnmarshalPubRSAPublicKey()` with `20ff ffff 2020 20ff ffff 2020` will cause a massive allocation, crashing the machine.

Given that `TPMUnmarshal` takes a reader, theres no upfront knowledge of the size of the buffer being processed.

Anyone have an opinion on these options?

1. Add a max size (maybe 1mb?) which is larger than all expected use-cases
2. Refactor `tpmutil.Unpack` to pass the size of the buffer down the chain so size prefix fields can be properly validated.

WDYT?

### Additional contract requirements

- When `Unpack` decodes a `U32Bytes` value with an oversized length prefix, it must return `bytes.ErrTooLarge`. When it decodes a `U16Bytes` value whose declared length exceeds the available input, it must return `io.ErrUnexpectedEOF`.
