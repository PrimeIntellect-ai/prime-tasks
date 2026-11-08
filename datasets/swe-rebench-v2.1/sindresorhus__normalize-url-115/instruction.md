Regex for removal of duplicate slashes not preceded by a protocol is too strict
```js
// Remove duplicate slashes if not preceded by a protocol
if (urlObj.pathname) {
  [HIDDEN]
}
```

Limiting the preceding protocol to only http or https is too strict. There are valid URLs that contain other protocols (ftp, s3, git, etc) as part of their path that are rendered invalid by this regex.

Example URLs broken by this regex:
* `http://sindresorhus.com/s3://sindresorhus.com` becomes `http://sindresorhus.com/s3:/sindresorhus.com`
* `http://sindresorhus.com/git://sindresorhus.com` becomes `http://sindresorhus.com/git:/sindresorhus.com`

Real world URL broken by this regex:
* https://images.megaphone.fm/8wdeoO3TExq3DnwqQWKXcWfnnGOJkA9kzcaZKo3Ue0M/plain/s3://megaphone-prod/podcasts/daef779e-0f93-11e9-8be1-ef6a540ab876/image/uploads_2F1561781562946-7xoryiijhz6-d6e84acd3033beaa78167923137f8d6c_2FEar_Biscuits_Profile_2019.jpg becomes https://images.megaphone.fm/8wdeoO3TExq3DnwqQWKXcWfnnGOJkA9kzcaZKo3Ue0M/plain/s3:/megaphone-prod/podcasts/daef779e-0f93-11e9-8be1-ef6a540ab876/image/uploads_2F1561781562946-7xoryiijhz6-d6e84acd3033beaa78167923137f8d6c_2FEar_Biscuits_Profile_2019.jpg

### Additional contract requirements

- The following are also required results: `http://sindresorhus.com/a://sindresorhus.com//foo` normalizes to `http://sindresorhus.com/a:/sindresorhus.com/foo`, and `http://sindresorhus.com/alongprotocolexceeds50charlimitxxxxxxxxxxxxxxxxxxxxx://sindresorhus.com//foo` normalizes to `http://sindresorhus.com/alongprotocolexceeds50charlimitxxxxxxxxxxxxxxxxxxxxx:/sindresorhus.com/foo`.
- Preserve valid protocol separators such as `s3://` and `git://` when they occur within a URL path, while continuing to remove duplicate pathname slashes that are not part of a protocol separator.
