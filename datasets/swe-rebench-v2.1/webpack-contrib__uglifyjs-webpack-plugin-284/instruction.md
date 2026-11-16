Unnecessary warning on "invalid source map" for JSON files
Hi everyone :)

When `import()`ing a json file, the generated source map is valid but "empty", which causes https://github.com/webpack-contrib/uglifyjs-webpack-plugin/pull/268/files#diff-8968c62593320351ced6a0ef776ef599R8 to fail and emit a warning.

See https://github.com/webpack-contrib/uglifyjs-webpack-plugin/pull/268

**Example:**

`data.json`
```json
{
	"hello": "world"
}
```

generates the following source map:

```json
{
 "version":1,
 "sources":[],
 "names":[],
 "mappings":"",
 "file":"data.8efcc96623969177ff47.js",
 "sourceRoot":""
}
```

[HIDDEN]

Even when using `SourceMapDevToolPlugin()` https://webpack.js.org/plugins/source-map-dev-tool-plugin/ and explicitely excluding source maps for such files the warning will still be added. This should definitely not happen, I guess? Of course there is "no valid source map", because there is no source map at all.

Ultimately it adds the following warning to the webpack compiler output:
> data.8efcc96623969177ff47.js contain invalid source map

Sidenote: There is a typo, it should be "contains".

Side-Sidenote: This "warning" comes without any "error stack" and is really, really hard to debug. Also searching on google / stackoverflow etc. is extremely hard because it's so generic and there is no way of knowing who warned me. Is it webpack? Babel? Typescript?

I only found the cause by change after intense searching and almost losing my mind. 🤪
Would love to see some improved message here too :)

Cheers and thank you,
Stefan

### Additional contract requirements

- Treat the empty source map shown above as valid, but do not treat incomplete objects or non-map values as valid source maps.
- Do not emit an invalid-source-map warning when an asset has no source map, including when source maps are explicitly excluded.
- The invalid-source-map warning message is exactly `<file> contains invalid source map`, where `<file>` is the name of the asset being processed (for example, `test4.js contains invalid source map`). The spelling is `contains`.
