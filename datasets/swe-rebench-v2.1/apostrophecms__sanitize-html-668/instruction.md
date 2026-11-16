Allow escaping of more than just tags
## The problem to solve

I would like the sanitised string to be displayed exactly as input. Discarding text is not helpful, as it will be missing.
`options.disallowedTagsMode = 'recursiveEscape'` already exists to escape tags instead of removing them. Attributes, etc. are still removed instead of escaped though.

User Story:
1. We start with (mostly) everything disallowed.
2. User attempts to input HTML, sees the resulting text and copy&pastes directly into a feature request to allow the tag/attribute/style/whatever they want and do not get.
3. (If the requested element can be safely allowed) we copy&paste the text directly into our mock project for TDD.
4. loop 2., 3.
5. Profit!

## Proposed solution

I, personally, would like a simple switch `options.disallowedEverythingMode: 'discard' | 'escape' | 'recursiveEscape'` or similar.

## Alternatives

Mirroring the lists and records of `options` akin to how the existing `options.disallowedTagsMode` mirrors `options.allowedTags` is probably the more sensible approach:
```
options.disallowedAttributesMode: 'discard' | 'escape' | 'recursiveEscape'
options.disallowedStylesMode: 'discard' | 'escape' | 'recursiveEscape'
<etc.>
```
Mayhap a synthetic "all the things" could be added as a function on top of those:
`function setDisallowedEverythingMode(mode: 'discard' | 'escape' | 'recursiveEscape') {/* set every flag to mode */}`

## Additional context

```
options: {
  allowedAttributes: {},
  allowedTags: [],
  disallowedTagsMode: 'recursiveEscape',
  nonTextTags: [],
  selfClosing: [],
}
```

Input: `"Cursed Project <img src=x onerror=alert('AllYourBaseAreBelongToUs!');>"`
Expected: `Cursed Project <img src=x onerror=alert('AllYourBaseAreBelongToUs!');>`
Displayed: `Cursed Project <img></img>`

### Additional contract requirements

The sanitizer must provide the boolean `preserveEscapedAttributes` option, defaulting to `false`. When it is `true`, attributes on disallowed tags must be retained in the escaped text produced by `disallowedTagsMode: 'escape'` or `'recursiveEscape'`, so the tags and their attributes can be seen and copied without becoming active markup. When it is `false`, those escaped tags omit their attributes.
