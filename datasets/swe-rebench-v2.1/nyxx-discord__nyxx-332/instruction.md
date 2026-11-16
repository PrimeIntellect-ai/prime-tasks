Implement forum channels
Ref: https://github.com/discord/discord-api-docs/pull/4761

### Additional contract requirements

Discord forum-channel payloads must be recognized as forum channels rather than generic channels. Forum channels must expose their available tags through a public property named `availableTags`, and each exposed tag must carry the Discord-provided `name` metadata as `name` and the `emojiName` metadata as `emojiName`. Provide `createThread(ForumThreadBuilder builder)` returning a created thread, and `fetchPublicArchivedThreads`, `fetchPrivateArchivedThreads`, and `fetchJoinedPrivateArchivedThreads`, each returning the corresponding archived thread results. `ForumThreadBuilder(String name, MessageBuilder message)` must allow a post name and its first message to be supplied when creating a forum post.
