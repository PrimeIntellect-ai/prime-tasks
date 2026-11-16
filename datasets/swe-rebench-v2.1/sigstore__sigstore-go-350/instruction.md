SCT verification should compare timestamp against CT log validity window
**Description**

<!--What needs to be improved? What should be done? Has there been any related work
before? Any relevant links or material?
-->

As a reminder, the purpose of validity windows is to mitigate two risks:

1. An old signing key for a service is compromised and produces an artifact after the service is turned down
2. A service that was turned down is brought back online and issues a cert or proof after it's been marked as rotated

I've been looking over the code and wanted to confirm if we are verifying validity windows for root metadata. Here's what I've found so far:

* TSA
  * The TSA validity window is compared to the TSA timestamp - https://github.com/sigstore/sigstore-go/blob/main/pkg/verify/tsa.go#L106-L111
  * [**Potential bug**] There is no comparison for the intermediate and root certificates.
* Rekor
  * The Rekor validity window is compared to the entry integrated time from the SET - https://github.com/sigstore/sigstore-go/blob/main/pkg/tlog/entry.go#L271-L277
  * [**Discussion topic**] There is no timestamp comparison during verification of a proof because there is no SET. We should not use the integrated timestamp because it is not signed. This means that we cannot verify a log proof was generated during a validity window.
* Fulcio
  * CA validity window is compared to the certificate's not before/after - https://github.com/sigstore/sigstore-go/blob/main/pkg/verify/certificate.go#L27-L32
  * [**Potential bug**] There is no comparison for the intermediate and root certificates.
* CT log
  * [**Potential bug**] It doesn't look like we compare the SCT timestamp to the CT log validity window in https://github.com/sigstore/sigstore-go/blob/main/pkg/verify/sct.go

In terms of how to structure the code, as is currently implemented, each service (CA, CT log, Rekor, TSA) should be responsible for comparing any of its artifacts that contain timestamps against the validity windows. TODOs below:

- [x] TSA compared against issued signed timestamps
- [x] TSA compared for each certificate in its chain
- [x] Rekor compared against issued SETs
- [x] CA compared against issued leaf certificates
- [x] CA compared for the root and intermediate CA certificates
- [ ] CT log compares against issued SCTs

The metadata I don't know how to verify is if a log proof was created during a log's validity window, since there is no timestamp. Using a certificate's timestamp is not accurate because a certificate may be logged long after a signing event. In the case of BYO PKI, there may also be no timestamps, if you log a signing event with a key. I think there's nothing to compare against in these cases.

### Additional contract requirements

- Add a public function `VerifySignedCertificateTimestamp(chains [][]*x509.Certificate, threshold int, trustedMaterial root.TrustedMaterial) error` in package `pkg/verify`.
- The public type `root.TransparencyLog` in package `pkg/root` exposes `PublicKey *rsa.PublicKey`, `ValidityPeriodStart time.Time`, and `ValidityPeriodEnd time.Time`.
- An SCT is excluded when its timestamp, converted from milliseconds since the Unix epoch, is before the corresponding CT log key's `ValidityPeriodStart` or after its `ValidityPeriodEnd`. A zero `ValidityPeriodStart` or `ValidityPeriodEnd` imposes no bound on that side.
