Implementation loop cursor not properly reset for multiple occurrences
When reading an input stream containing multiple occurrences of an implementation loop not in the exact order specified in the implementation schema, occurrences fail to match earlier discriminator values once they are passed the first time.

E.g. 837 implementation loops received:
- 2000A
- 2000B
- 2000C
- 2000A
- 2000B
- 2000C

Would be incorrectly processed as:
- 2000A
- 2000B
- 2000C
- 2000C
- 2000C
- 2000C

### Additional contract requirements

- For implementation validation, emit a `SEGMENT_ERROR` with error type `IMPLEMENTATION_LOOP_OCCURS_UNDER_MINIMUM_TIMES` and reference code `S11` immediately after the `END_LOOP` event with reference code `0000D`.
