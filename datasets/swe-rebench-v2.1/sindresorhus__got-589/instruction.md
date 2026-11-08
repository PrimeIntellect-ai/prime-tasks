Custom URL query scheme is modified
I need to perform requests against an external API that has a custom encoding scheme in the query. More specifically, it requires that the caller put an unencoded URL at the very end of the query string.

While this is perfectly valid as a URL, `got` seems to assume that query strings are formatted as `key1=value1&key2=value2` etc and is first parsing and then re-serializing the query with that assumption in mind. See:
https://github.com/sindresorhus/got/blob/1c54a03bc6a809b73970f1694d3fccd22b664997/source/normalize-arguments.js#L113

However, this means that you no longer support custom query schemes which are perfectly valid URLs? Note that the URL spec does not require a particular query encoding scheme as long as you comply with the allowed character sets.
