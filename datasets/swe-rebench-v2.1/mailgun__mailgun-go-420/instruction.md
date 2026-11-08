The ListIPs call's return value is incomplete
As per the [List account IPs](https://documentation.mailgun.com/docs/mailgun/api-reference/openapi-final/tag/IPs/#tag/IPs/operation/GET-v3-ips) endpoint's documentation there are additional response fields which are currently unsupported by `mailgun-go`. Such fields are `assignable_to_pools`, and `is_on_warmup` within the `details` list.

There seems to be two ways to extend the current functionality:

1. Changing the return value of the `ListIPs` function's return type to resemble the API response more closely. This would yield a breaking change in the public API, so probably would come with a major version bump.
2. Introducing a new `IPAddress`-ish mtype which contains the `assignable_to_pools` and `is_on_warmup` flags. This would be separate from the existing `IPAddress` mtype which has the `dedicated` flag. Changing the return type to the new mtype would be just a minor change, as the `ListIPs` function currently only populates the `IP` property, even if the `dedicated` flag is set in the call.

Please let me know which is the desired way forward or if there is a third option which would be better. I am happy to do the implementation.

### Additional contract requirements

Each IP returned by `ListIPs` exposes whether it is assignable to pools and its warm-up status from the corresponding IP details in the account response.
