[proposal] Improvements to the verification API
**Is your feature request related to a problem? Please describe.**

The verification of JWT/JWS uses exceptions to signal failures, but this creates a problem in distinguishing between legitimate failures (bad signature, invalid audience, timestamp issue, etc) and exceptional situations (network timeout while resolving DID, malformed input, unsupported algorithm, etc).

I propose separating these 2 scenarios internally so that users get a better idea about what failed and so that control flow for invalid JWTs no longer relies on parsing error messages.

**Describe the solution you'd like**
The result of `verifyJWT()` should be an object with a `verified` property set to true only when signature, timestamps, and audience are valid, and false otherwise.
When one of the validation criteria fails, the reason can be returned as an error code with a message.
`verifyJWT()` should not throw errors.

The verification options should accept a `now` parameter for checks involving past/future validity, or allow the user to disable timestamp checking. Similarly, it should be possible to skip audience checking (although, this is already indirectly possible by pre-inspecting the desired audience).

**Describe alternatives you've considered**
The desired behavior can already be achieved by calling `verifyJWS` directly for signature checks and by performing timestamp and audience checking out of band, but that defeats the purpose of having a library to do this.

Another acceptable solution would be to introduce a new method (`verifyJWTSafe`) that can give detailed reasons for failure without using exceptions for flow control, while leaving the existing `verifyJWT` method intact for backward compatibility.

Please add your opinion about this subject if you have one.

### Additional contract requirements

- On a successful verification, the resolved object has `verified` set to `true`.
- When a validation criterion fails (invalid signature, invalid audience, or a timestamp violation), the returned promise rejects with an `Error`.
- For these validation failures the outcome is a rejection, not a resolved result: a failed verification never resolves with `verified` set to `false`, and the rejection takes precedence over the earlier statements in this issue that `verifyJWT()` should not throw and should return `verified: false`.
- Callers can disable audience validation independently of the expected audience by setting `policies.aud` to `false`; a JWT with a non-matching audience can then verify successfully when its other checks pass.
