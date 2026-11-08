Verifying a protected generic method that returns a value is broken
This Verify method [HIDDEN], so this method will always throw an error because it thinks no generic type arguments were provided even though they were.

https://github.com/moq/moq4/blob/d535cc40870362f9667b64de1308fda3c204e6b8/src/Moq/Protected/ProtectedMock.cs#L253

### Additional contract requirements

- Verifying a protected generic method that returns a value must honor the supplied generic type arguments when matching invocations, rather than treating them as absent.
