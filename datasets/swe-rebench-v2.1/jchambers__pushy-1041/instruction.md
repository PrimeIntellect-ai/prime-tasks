couple of Live Activity issues: stale-date is missing, and relevance-score can now have a value greater than 1.0
Hi folks!  Just spent some time working with Live Activities and have a couple of issues I ran into:

1. "stale-date" is another live activity-related field that would be useful to support, similar to "dismissal-date" which was [added in these lines](https://github.com/jchambers/pushy/pull/990/files#diff-18de686d2d85ad5f1d21f98b4ea6ef93519cb8e246fa4f1cfcf4a68688ebed24R872-R874). More info at [the Apple docs](https://developer.apple.com/documentation/activitykit/updating-live-activities-with-activitykit-push-notifications#:~:text=To%20mark%20a%20Live%20Activity%20as%20outdated%20with%20an%20update%2C%20optionally%20set%20the%20stale%2Ddate.%20For%20more%20information%2C%20see%20the%20%E2%80%9CMark%20a%20Live%20Activity%20as%20outdated%20by%20setting%20a%20stale%20date%E2%80%9D%20section%20below.).

2. The other issue is that "relevance-score" is now permitted to have a higher value than previously, [judging by these Apple docs](https://developer.apple.com/documentation/activitykit/updating-live-activities-with-activitykit-push-notifications#:~:text=The%20system%20expects%20relative%20values%20for%20the%20relevance%20score.%20Assign%20a%20higher%20value%20for%20an%20important%20Live%20Activity%20content%20update%20%E2%80%94%20for%20example%2C%20a%20score%20of%20100%20%E2%80%94%20and%20use%20lower%20values%20for%20less%20important%20Live%20Activity%20content%20updates%20%E2%80%94%20for%20example%2C%2050.).  As I understand it, this previously was [limited to a value between 0 and 1](https://developer.apple.com/documentation/usernotifications/unnotificationcontent/3821031-relevancescore) -- so I guess this limit is no longer applied? and [HIDDEN]  Thoughts?

### Additional contract requirements

- Add a public method `setStaleDate(java.time.Instant staleDate)` to `com.eatthepath.pushy.apns.util.ApnsPayloadBuilder` that returns the same `ApnsPayloadBuilder` instance.
- When a non-null instant is provided, it is encoded as a Unix epoch-seconds value under the `stale-date` key inside the payload's `aps` dictionary.
- Passing `null` clears the stale-date field so that no `stale-date` entry appears in the payload.
- The relevance score is not restricted to the former 0-to-1 range; values greater than 1.0 must be accepted.
