SigningConfig should select the highest API version when possible
**Description**

<!--Tell us about the bug. What went wrong? How can we reproduce it? What should the correct behavior be?
-->

**Version**

<!--What version are you using? e.g. `cosign version`...
-->

Right now, when selecting a service or set of services, the SigningConfig will select the first match given a validity period and API version. If the client supports two API versions concurrently (e.g. Rekor v1 and Rekor v2) and the distributed signing config has entries for multiple API versions (which it will for Rekor), then the client may select an older API version depending on the sorting of the services.

I will also update the language in protobuf-specs to be more prescriptive on how clients should select a service given support for multiple API versions.
