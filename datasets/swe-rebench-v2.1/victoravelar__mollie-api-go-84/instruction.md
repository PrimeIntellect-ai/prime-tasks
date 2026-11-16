Include new Gift card issuers
**Is your feature request related to a problem? Please describe.**
New gift cards issuer had been enabled by Mollie, it will be good if we include support to have full compatibility.

## ⚠️  Update - 03-10-2020
Main focus of this ticket should change towards the enable and disable gift card issuers in Profiles API
- [Enable gift card issuer for profile](https://docs.mollie.com/reference/v2/profiles-api/enable-gift-card-issuer)
- [Disable gift card issuer for profile](https://docs.mollie.com/reference/v2/profiles-api/disable-gift-card-issuer)

### August
- Thursday, 20th: Added `good4fun` as gift card issuer.
- Monday, 10th: Added `decadeaukaart` as gift card issuer.


### April 2020
- Friday, 3rd:
   - Added `restaurantcadeau` as gift card issuer.
   - Added `dinercadeau` as gift card issuer.

**Describe the solution you'd like**
The afore mentioned issuers are included as gift card issuer constants.

### Additional contract requirements

Expose `GiftCardIssuer` and the constants `Good4fun`, `DecaudeuKaart`, `Restaurantcadeau`, and `Dinercadeau`, whose values are `good4fun`, `decadeaukaart`, `restaurantcadeau`, and `dinercadeau`, respectively.

Provide `ProfilesService.EnableGiftCardIssuer(profileID string, issuer GiftCardIssuer)`, which enables the issuer for the specified profile and returns its `*GiftCardEnabled` data on success. It returns an error if the request fails or its response cannot be decoded. Provide `ProfilesService.DisableGiftCardIssuer(profileID string, issuer GiftCardIssuer)`, which disables the issuer for the specified profile and returns an error if the request fails.
