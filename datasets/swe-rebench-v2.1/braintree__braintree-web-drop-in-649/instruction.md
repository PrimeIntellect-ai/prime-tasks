Add a method to Drop-in UI to return supported payment types
### General information

* SDK/Library version: 1.22.0
* Environment: Sandbox and Production
* Browser and OS: any browser

### Feature request

I have a requirement to be able to detect whether or not Venmo is supported on the client browser, in order to provide further instructions to the user.  This would be useful for any other payment method as well.

I currently use a workaround where I check an array within "clientInstance" parameter, however this is not guaranteed to work with future releases.

[HIDDEN]

Please add a method like "clientInstance.isSupportedPaymentMethod(_paymentMethod_)".

See support ticket #2723511 for reference.

### Additional contract requirements

Expose `Dropin.getAvailablePaymentOptions()` as a public method. It returns an array of identifiers for the payment options presented to the customer, so callers can determine whether Venmo or another payment option is supported for that client. The order of identifiers is not significant.
