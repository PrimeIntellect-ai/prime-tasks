Multiple Drop-in instances may cause PayPal to fail to load
### General information

* SDK/Library version: `1.9.4` and `1.22.0`.
* Environment: Sandbox and Production.
* Browser and OS: Windows 7 64-bit, Chrome, Version 79.0.3945.130 (Official Build) (64-bit)

### Issue description

To reproduce the issue:
1. Visit https://www.bitarmory.com/bogus
1. In the DropIn UI, select "Card" for "Choose a way to pay".
   ![image](https://user-images.githubusercontent.com/478118/73320114-2f9e8e00-41f3-11ea-9432-5e2c903e75cb.png)
1. Open DevTools, and type in console: `dropin.clearSelectedPaymentMethod()`. The `dropin` variable is a saved instance of the `dropinInstance` after initialization.
1. After calling `dropin.clearSelectedPaymentMethod()` method, the UI does not go back to payment options.
   ![image](https://user-images.githubusercontent.com/478118/73320210-6b395800-41f3-11ea-94e1-8dc52abbc597.png)
1. Calling `dropin._mainView.toggleAdditionalOptions()` works; but this API is undocumented. :disappointed:
   ![image](https://user-images.githubusercontent.com/478118/73320313-b81d2e80-41f3-11ea-9b0f-c6aeaa7a3a62.png)

The issue is in production and sandbox for versions `1.22.0` latest and `1.9.0`.

### Additional contract requirements

- The PayPal button is rendered through the PayPal SDK's `paypal.Button.render(config, selector)` call. The `selector` argument must be scoped to the current Drop-in instance's wrapper element: it must start with the instance's wrapper ID, `#braintree--dropin__<componentID>`, followed by the button's data attribute selector, `[data-braintree-id="paypal-button"]` for the standard PayPal button or `[data-braintree-id="paypal-credit-button"]` for the PayPal Credit button.
- `paypal.Button.render` returns a Promise that resolves once the button has been rendered, and errors from the PayPal SDK are propagated.
