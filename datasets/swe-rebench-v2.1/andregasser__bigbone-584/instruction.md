Update Instance entity with 4.4.0 attributes
According to [Trunk & Tidbits March 2025](https://blog.joinmastodon.org/2025/04/trunk-tidbits-march-2025/), the `Instance` entity has been updated with at least the following:

- new fields in the instance endpoint to get the instance’s about, terms of service and privacy policy pages
- an attribute to the instance endpoint to understand whether a reason is required for sign up

These need to be added to our Instance entity.

### Additional contract requirements

The instance entity exposes the about-page URL as `about`, the terms-of-service URL as `termsOfService`, and the privacy-policy URL as `privacyPolicy`. These URLs are provided by the instance response's configuration URL fields. The instance registration policy exposes whether a reason is required for sign-up as `reasonRequired`.
