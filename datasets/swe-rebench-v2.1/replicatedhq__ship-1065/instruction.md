Template function ShipCustomerRelease in config map produces error data too long
### Expected behavior

I should be able to follow this guide for a titled installation https://help.replicated.com/docs/ship/playbooks/entitlements/

### Actual behavior

When i try to deploy the release yaml I get the following error:

```
The ConfigMap "titled" is invalid: metadata.annotations: Too long: must have at most 262144 characters
```

### Information

- Ship version: 0.51.0
- Command line run: ship init replicated.app/myslug
