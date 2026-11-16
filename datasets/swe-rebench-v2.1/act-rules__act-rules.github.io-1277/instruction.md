Failed example 3 wrong for 'role attribute has valid value'
## Failed example 3
```
<input type="text" role=" " />
```
https://act-rules.github.io/rules/674b10#failed-example-3

## Inapplicable example 1
```
<div role="">Some Content</div>
```

The roles in these examples are both equivalent since the value is space separated tokens, so both should be inapplicable or both failed. See step 1 B here:
https://www.w3.org/TR/wai-aria-implementation/#mapping_role

Both of these produce the same empty list of roles.

ARIA 1.2 does define token list as:
> A list of one or more tokens
https://www.w3.org/TR/wai-aria-1.2/#host_general_role

This is unlikely to be harmful since ARIA also says only the first valid, concrete role should be applied:
>If the role attribute contains no tokens matching the name of a non-abstract WAI-ARIA role, the user agent MUST treat the element as if no role had been provided
https://www.w3.org/TR/wai-aria-1.2/#document-handling_author-errors

...but it is classed as an ARIA authoring error...

*Edit:*  ... which is an ARIA conformance issue, but not guaranteed to be a WCAG conformance issue (especially if devs have randomly sprinkled role='' over their code). Generally valid roles used inappropriately are a much worse problem. For example:
```
<body role='presentation'>
````

*Note:* ARIA doesn't define which characters are whitespace, but the actual algorithm used by browsers is very likely to be this one since browsers already use this for `class` and `autocomplete` attributes:
https://html.spec.whatwg.org/multipage/common-microsyntaxes.html#space-separated-tokens

**Update:** HTML is very inconsistent regarding empty vs whitespace-only attributes vs leading and trailing whitespace:

`alt=''` is not the same as `alt='  '`
`lang=''` is not the same as `lang='  '`
`id='test'` is not the same as `lang=' test '`
`class=''` is the same as `class='  '`
`class='test'` is the same as `class=' test '`
`role=''` is the same as `role=' '`
`role='img'` is the same as `role=' img '`

### Additional contract requirements

- A whitespace-only `role` value and an empty `role` value receive the same classification.
- Leading and trailing whitespace around a valid `role` token do not prevent that token from being considered.
