Fallback URL for streaming API seems malformed
Hi,

First thank you very much for providing this library. I'm working on a social wall project for Mastodon and bigbone is a huge help.

During a try to implement an end to end test with Mastodon in a container i stumbled across the fallback URL for the streaming API. The fallback was triggered since I tried the `LIMITED_FEREDATION_MODE` in the Mastodon .env file. After enabling that, the `/api/v2/instance` endpoint is only accessable after authentication and so the fallback in your [MastodonClient](https://github.com/andregasser/bigbone/blob/de0dbc7718dff43ea1a807474640524cd3e3df4a/bigbone/src/main/kotlin/social/bigbone/MastodonClient.kt#L1041C1-L1041C87) is used:

`
[HIDDEN]
`

While debugging it became clear, that the constructed URL is missing the seperator between the scheme and the instanceName. E.g. if my container with mastodon is reachable via https as `mymastodoninstance` it is `httpsmymastodoninstance`. But it should be `https://mymastodoninstance`.

I'm not adapted to Kotlin yet so I can't provide a unit test at the moment. But maybe in the future.
Do you need any other information to verify this?

Kind regards
seism0saurus
