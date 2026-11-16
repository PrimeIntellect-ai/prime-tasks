Feature request: implement a subscriber API to align with other SDK offerings
**Is your feature request related to a problem? Please describe.**

We are trying to log toggle status changes so that we know when exactly those changes have been applied to the application, but we have no way to subscribe to those events.

**Describe the solution you'd like**
A solution [similar to the JDK's SDK](https://docs.getunleash.io/reference/sdks/java#subscriber-api) which allows us to create subscribers to different events so that our applications can act upon those events.

**Describe alternatives you've considered**
For now we will probably manually keep track of the status of the toggles and wrap the `is_enabled` call so that when we notice a status change we can print a log. Either that or try to override the `fetch_and_load_features` function somehow.

**Additional context**
N/A

### Additional contract requirements

- Applications receive SDK events by passing a callable as `event_callback` to `UnleashClient`. Each event delivered to that callable has an `event_type` attribute holding a member of `UnleashEventType`, so the application can tell the kinds of event apart.
- After the client has fetched feature toggles from the Unleash server and loaded them, the callable receives an event whose `event_type` is `UnleashEventType.FETCHED`. This event exposes the fetched toggles through a `features` attribute, which is the list of toggle dictionaries returned by the server (each dictionary has a `name` key).
- Feature flag evaluations and variant evaluations continue to be delivered to the callable as events of type `UnleashEventType.FEATURE_FLAG` and `UnleashEventType.VARIANT`, carrying the feature name, the evaluation result and, for variants, the variant name.
