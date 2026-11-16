SD-JWT Holder/Verifier - Process Disclosures
Add utility function to decode disclosures (will be used by both holder and verifier)

Create disclose claims function for holder that will re-create SD-JWT with disclosures for selected claims only.

Verifier should insert decoded claims (claim name/value) at the level of the _sd claim and remove _sd_claims and _sd_alg from SD-JWT payload.

### Additional contract requirements

- Provide `common.GetDisclosureClaims(disclosures []string) ([]*common.DisclosureClaim, error)` to decode disclosure strings. Each returned claim exposes its original disclosure in `Disclosure`, its `Salt`, its claim `Name`, and its decoded `Value`; malformed disclosures return an error.
- Provide `holder.DiscloseClaims(sdJWTSerialized string, claimNames []string) (string, error)`. The result preserves the signed JWT and includes only disclosures whose claim names were selected. Return an error if the input has no disclosures or a disclosure is malformed.
- Provide `verifier.Parse(sdJWTSerialized string, opts ...ParseOpt) (map[string]interface{}, error)`. On success, each disclosed claim appears by its decoded name and value alongside ordinary JWT claims. The returned payload omits the SD-JWT `_sd` and `_sd_alg` internal claims.
