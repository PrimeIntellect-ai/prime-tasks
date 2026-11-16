Adoption errors cause deprovisioning
If a Host is in the `provisioned` state and an error occurs during Adopt() (i.e. a `provisioned registration error`), the Host will be deprovisioned. This is bad.

The same does _not_ apply to ordinary `registration error` errors, because registration is handled separately.

It _would_ apply to `power management error`, but we have never reported a power management error (c.f. #828), and won't until #841 is merged.
