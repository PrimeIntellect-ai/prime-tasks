Type aliases should support the @format tag
## Sorting

* **I'm submitting a ...**
  - [ ] bug report
  - [x] feature request
  - [ ] support request

* I confirm that I
  - [x] used the [search](https://github.com/lukeautry/tsoa/search?type=Issues) to make sure that a similar issue hasn't already been submit

## Expected Behavior
Format tag attached to an alias should generate a format requirement
```ts
/**
 * @format email
 */
export type StringAlias = string;
```
```json
"StringAlias": {
  "type": "string",
  "format": "email"
}
```

## Current Behavior
No format is generated for type aliases

```ts
/**
 * @format email
 */
export type StringAlias = string;
```
```json
"StringAlias": {
  "type": "string"
}
```

## Detailed Description
Format specification would be especially useful for type aliases as it would allow centralizing type information. This should be an extremely simple change.
