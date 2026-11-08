unmarshal error in billing.go - GetStorageBillingOrg function
Hello - Am trying to get the storage stats for my GitHub org from GetStorageBillingOrg function, But it throws error.
Details as follows.

_Go version used_: go1.17.2 linux/amd64
_Operating system_: Ubuntu
_Function reference_: https://github.com/google/go-github/blob/master/github/billing.go#L79

_Error_:`json: cannot unmarshal number 19.5361328125 into Go struct field StorageBilling.estimated_paid_storage_for_month of type int`

The output is on float but the struct field is of type int
https://github.com/google/go-github/blob/master/github/billing.go#L41-L45


Below is my custom function code:
```
func storage(ctx context.Context, client *github.Client, org string) {
	str, _, err := client.Billing.GetStorageBillingOrg(ctx, org)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(str)
}
```
Am able to get the response from GitHub API though
```
curl -s -u $gituser:$token -H "Accept: application/vnd.github.v3+json" https://api.github.com/orgs/$org/settings/billing/shared-storage
{
  "days_left_in_billing_cycle": 16,
  "estimated_paid_storage_for_month": 19.4375,
  "estimated_storage_for_month": 69
}
```

### Additional contract requirements

- `StorageBilling` is a public struct in package `github`. Its `EstimatedPaidStorageForMonth` field must be a `float64` so that the fractional values returned by the API (for example `19.4375`) are accepted; its `DaysLeftInBillingCycle` and `EstimatedStorageForMonth` fields remain `int`.
- `BillingService.GetStorageBillingOrg(ctx context.Context, org string) (*StorageBilling, *Response, error)` returns the shared-storage billing summary for the organization named by `org`.
- `BillingService.GetStorageBillingUser(ctx context.Context, user string) (*StorageBilling, *Response, error)` returns the shared-storage billing summary for the named user.
