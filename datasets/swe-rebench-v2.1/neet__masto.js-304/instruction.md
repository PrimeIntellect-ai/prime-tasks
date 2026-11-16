Repeated "MastoUnprocessableEntityError" on upgrade from masto.js 2.x to 3.x
Hi, I upgraded from `masto@2.5.4` to `masto@3.5.1` and renamed the `uploadMediaAttachment` method and response object parameters as indicated by the [breaking changes in the release notes for 3.0.0](https://github.com/neet/masto.js/releases/tag/v3.0.0), but now I'm getting a `MastoUnprocessableEntityError` whenever I try to make a post with uploaded media. Previously it used to work fine.

The full error:

> MastoUnprocessableEntityError: Cannot attach files that have not finished processing. Try again in a moment!

The code I was using with `masto@2.5.4`, which worked fine:

```ts
// ...

const { id } = await masto.uploadMediaAttachment({
  file: createReadStream(filename),
  description: title
});

const { created_at, uri } = await masto.createStatus({
  status: title,
  visibility: "public",
  media_ids: [id]
});
```

The code I am using with `masto@3.5.1`, which throws the exception:

```ts
// ...

const { id } = await masto.createMediaAttachment({
  file: createReadStream(filename),
  description: title,
});

const { createdAt, uri } = await masto.createStatus({
  status: title,
  visibility: "public",
  mediaIds: [id],
});
```

Is it possible this is a change in the Mastodon API behaviour [introduced in 3.1.0](https://github.com/neet/masto.js/releases/tag/v3.1.0) when using the `v2/media` endpoint? If so, that seems like a breaking change.

### Additional contract requirements

The Masto client must expose `fetchMediaAttachment(id)` to retrieve an uploaded attachment and `waitForMediaAttachment(id)` to wait for processing to complete before using the attachment in a status. Waiting must continue checking until the attachment URL is available and resolve with the completed attachment.
