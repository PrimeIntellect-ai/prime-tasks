Uncaught exception in WebMessageHandler's eventValidator when event.data is null
### Describe the problem

In https://github.com/auth0/auth0.js/blob/master/src/web-auth/web-message-handler.js#L17 there's a check for the `event_type` as `eventData.event.data.type`, but in the case that the event doesn't contain a `data` property, this throws an uncaught exception.

This seems to happen at least with the Google Tag Manager module of Cookiebot, whose event ends up in the validator of auth0-js. This event doesn't contain a `data` property, which makes the validator throw.

### What was the expected behavior?

The exception should be handled gracefully in case the validated event doesn't contain a `data` property.

### Environment

- **Version of Auth0.js used:** 9.14.2
- **Which browsers have you tested in?** Chrome 87.0.4280.141, Firefox 84.0.2
- **Other modules/plugins/libraries that might be involved:** Cookiebot GTM (Google Tag Manager) module
