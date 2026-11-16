keyOverride prop rendering as an attribute on meta tags
**Describe the bug**
There's a `keyOverride` property you can pass to meta tags to distinguish multiple tags with the same name (see #638). [HIDDEN]

This results in a rendered attribute of `keyoverride` on the resulting `meta` tag, which is invalid.

**Reproduction**
Todo, sorry not had chance yet

**Expected behavior**
Expected result is the provided `keyOverride` prop is used for the internal `key` prop but not rendered as an attribute.

**Additional context**
#638 is related and how I discovered it. #666 is where the functionality was added.

It's worth saying the same issue doesn't happen for `link` tags because they use a combination of `rel` and `href` for the generated `key` prop:

https://github.com/garmeeh/next-seo/blob/815e6361e900ad7d6c219a552f1456076d8bec13/src/meta/buildTags.tsx#L658
