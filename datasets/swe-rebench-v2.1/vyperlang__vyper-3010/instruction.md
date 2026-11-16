CBOR section at end should include length indicator like in Solidity
## Simple Summary

PR #2860 introduced a CBOR section at the end of Vyper bytecode, like Solidity has.  However, unlike in Solidity, there's nothing to indicate the length of this CBOR section.  While it's easy enough to recognize the fixed format used in 0.3.4 (since it always has a length of 11 and only the last 3 bytes vary), if this format changes so that the length changes, bytecode disassemblers and analzyers will need to know about every possible format used in order to determine where the CBOR starts.

As such, like in Solidity, the CBOR section should be followed by a length indicator so we can determine the demarcation between the code and the CBOR.

## Motivation

Covered above.

## Specification

Depends on how you want to do it!  If you want to mimic Solidity exactly, the CBOR section would be followed by a 2-byte big-endian number representing the length of the CBOR section (the length does not include the 2 bytes itself).  But any way works so long as it's reliably locatable.

## Backwards Compatibility

There should be no substantial backwards incompatibility.  If any bytecode disassemblers or analyzers are accounting for the old format, they'll need to account for the new format as well, but the old format is already absent prior to 0.3.4, so...

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/)

### Additional contract requirements

- The compiled bytecode (both the deployment bytecode and the runtime bytecode) must end with the CBOR metadata section, followed by a 2-byte big-endian unsigned integer. That integer is the length in bytes of the CBOR metadata section, not counting the two length bytes themselves. This follows the Solidity convention, so a consumer can read the last two bytes to find where the CBOR section starts.
- The CBOR metadata section begins with the existing Vyper version map, `a1 65 76 79 70 65 72` (`{"vyper": ...}`).
