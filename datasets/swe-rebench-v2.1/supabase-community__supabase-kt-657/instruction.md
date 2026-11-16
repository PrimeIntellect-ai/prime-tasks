[Feature request]: Add a way to verify an OTP from a token hash
### General Info

- [X] I installed the latest version of Supabase Kt
- [X] I checked for similar feature requests

### Feature request

Add a `fun verifyEmailOtp(type: OtpType.Email, tokenHash: String)` function to verify an OTP from a token hash. This feature is present in official Supabase SDKs such as the JS SDK (see [verifyOtp](https://supabase.com/docs/reference/javascript/auth-verifyotp)) and Swift SDK (see [merged PR](https://github.com/supabase/supabase-swift/pull/451)).

### Usecase

This would be very useful when verifying an OTP coming from a link sent by email.

### Additional contract requirements

- `verifyEmailOtp(type: OtpType.Email, tokenHash: String)` must be callable with exactly those two arguments; the `captchaToken` parameter is optional and defaults to `null`.
- Passing `captchaToken = null` (or omitting it) must be accepted and must send the verification request without a captcha token.
