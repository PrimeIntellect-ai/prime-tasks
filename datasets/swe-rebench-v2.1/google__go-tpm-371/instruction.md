Invalid handling of KnownName() and Empty Buffer responses
KnownName() has a case for `TPMHTTransient` that conflates transient handles with sequence object handle values of a TPMS_CONTEXT.  Undefined behavior will result when more than one transient handle exists.

The TPM specification also defines an Empty Buffer as the Name for sequence objects (Part 1: Architecture, section 32.4.5), which is a special case that must be handled for `TPM2_SequenceUpdate` and `TPM2_SequenceComplete` commands.  Users of the library will receive command errors of the form:

```text
SequenceComplete failed: missing Name for 'SequenceHandle' parameter
```

This error should not occur because `Name` for these commands is the Empty Buffer.
