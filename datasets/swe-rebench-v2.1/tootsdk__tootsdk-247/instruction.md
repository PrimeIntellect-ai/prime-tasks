Inconsistent order of media attachments for scheduled posts
Hey 👋,
I'm building an app to schedule posts and noticed that the `mediaAttachments` and `params.mediaIds` in `ScheduledPost` have inconsistent ordering. `params.mediaIds` appears to have the correct order, while `mediaAttachments` are sorted numerically by their id. I'm not sure whether this would be considered to be a bug in the Mastodon API, but it would be nice to have consistent ordering in TootSDK. If you agree, I can create a pull request to [HIDDEN]

### Additional contract requirements

- When `params.mediaIds` is present, order a decoded `ScheduledPost`’s `mediaAttachments` to match it.
