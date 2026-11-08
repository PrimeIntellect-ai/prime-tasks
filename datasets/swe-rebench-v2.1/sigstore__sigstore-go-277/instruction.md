Certificate time is always valid when no timestamp is provided
Following up from https://github.com/sigstore/sigstore-go/issues/193#issuecomment-2297158885, we are using the [certificate's timestamp to verify itself](https://github.com/sigstore/sigstore-go/blob/d19dc5bd33f20e43bf49eaafcaeded0173c6b526/pkg/verify/signed_entity.go#L733-L738). This will always pass the time verification because a certificate's "not before" time always falls in the range of "not before" to "not after".

Instead, we should only use current time to verify a certificate's validity. I've started making the change, but some tests are failing, so I wanted to check if I'm missing something and this behavior is what you had expected from the policy flag?

@codysoyland @steiza @cmurphy

### Additional contract requirements

- Add a public function `WithCurrentTime() VerifierOption` in package `pkg/verify`. When a verifier is configured with this option, it validates the signing certificate against the current wall-clock time instead of requiring an observer timestamp, so a certificate that is not valid at the current time fails verification.
