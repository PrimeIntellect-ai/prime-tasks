Decoding error when getting Instance information from Pixelfed server
Pixelfed server is running latest version (0.12.3 as of this bug).

Attempting to call `client.getInstanceInfo()` throws a decoding error:
> decodingError("Type \'Int\' mismatch:Expected to decode Int but found a string instead.\n codingPath:[CodingKeys(stringValue: \"stats\", intValue: nil), CodingKeys(stringValue: \"statusCount\", intValue: nil)]")

This seems related to a recent change to the Pixelfed API (that's likely a bug, per [this issue](https://github.com/pixelfed/pixelfed/issues/5178), as it deviates from the Mastodon spec).

In a case like this, I don't know if a workaround makes sense in this SDK or wait and see if they address this bug in a future release.

### Additional contract requirements

Instance information from Pixelfed must decode when its status count is encoded as a numeric string. The decoded status count must be available as an integer.
