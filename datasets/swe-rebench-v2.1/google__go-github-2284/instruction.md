GitHub Actions Billing returns total_paid_minutes_used as float64
GitHub returns the `total_paid_minutes_used` value as float64 in the `/orgs/{org}/settings/billing/actions` endpoint.
Currently an Int is expected.

## Example
```bash
curl -H "Authorization: Bearer <TOKEN>" \
-H "Accept: application/vnd.github.v3+json"  \
https://api.github.com/orgs/{org}/settings/billing/actions
```
```json
{
  "total_minutes_used": 1234,
  "total_paid_minutes_used": 3959.0,
  "included_minutes": 3000,
  "minutes_used_breakdown": {
    "UBUNTU": 1234,
    "MACOS": 1234,
    "WINDOWS": 0
  }
}
```
