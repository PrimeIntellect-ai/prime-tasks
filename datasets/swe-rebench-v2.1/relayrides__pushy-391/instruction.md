Auto-collapsing alert dictionary into string
Long ago there was an advice in Apple's documentation:
> Don't specify a dictionary as the value of alert if the dictionary only has the body property

And Pushy's ApnsPayloadBuilder does exactly that -- it collapses `alert:{body:"text"}` into `alert:"text"`.
But now [the page containing the advice](https://developer.apple.com/library/content/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/Chapters/TheNotificationPayload.html#//apple_ref/doc/uid/TP40008194-CH107-SW10) is no longer available and [new version of documentation](https://developer.apple.com/library/content/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/PayloadKeyReference.html#//apple_ref/doc/uid/TP40008194-CH17-SW2) says the opposite:
> The **preferred value** for this key is a **dictionary**, the keys for which are listed in Table 9-2.

So I would like to have some kind of "switch" to enable/disable auto-collapsing of the `alert` dictionary into a string.

### Additional contract requirements

`ApnsPayloadBuilder.setPreferStringRepresentationForAlerts(boolean)` selects the representation of a body-only alert: `true` produces the alert body as a JSON string, and `false` produces a JSON dictionary with the body under the `body` key.
