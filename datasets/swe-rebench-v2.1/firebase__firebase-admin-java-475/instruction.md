Global VerifyIdToken() fails when token has a tenantId
  * Operating System version: Windows 10 2004
  * Firebase SDK version: 7.0.0
  * Library version: Not sure
  * Firebase Product: Auth (auth, database, storage, etc)

When a tenant Firebase JWT token is verified using the FirebaseAuth.verifyIdToken() this fails. This is in direct conflict to the google documentation for Google Identity Platform docs (https://cloud.google.com/identity-platform/docs/multi-tenancy-managing-tenants#identity_verification).

The exception message thrown is: "com.google.firebase.auth.FirebaseAuthException: The tenant ID ($MY_TENANT_ID) of the token did not match the expected value ('')"

It's worth noting this does not occur using the Node.JS version of the Firebase Admin SDK.

To reproduce Try and verify a Firebase JWT with a tenant with the global FirebaseAuth.verifyIdToken() method.

The issue appears to be that [HIDDEN] (makes sense there is no tenant here). [HIDDEN]

[HIDDEN] Otherwise you will need to:
* decode the token first to get the tenant Id
* create a TenantAwareFirebaseAuth instance
* verify the token.

### Additional contract requirements

- `FirebaseAuth.verifyIdToken()` must successfully verify a valid tenant-bearing Firebase JWT directly, without requiring callers to decode it first or create a tenant-aware auth instance, and the returned decoded token must expose its tenant ID.
- Tenant-scoped verification must accept a token with the matching tenant ID and reject a token with a different tenant ID or no tenant ID.
