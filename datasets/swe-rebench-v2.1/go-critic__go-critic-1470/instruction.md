Check if deprecation comment is in a seperate paragraph.
The Go documentation states that a deprecated comment should be in a separate paragraph:

> To signal that an identifier should not be used, add a paragraph to its doc comment that begins with Deprecated: followed by some information about the deprecation, and a recommendation on what to use instead, if applicable. The paragraph does not have to be the last paragraph in the doc comment.

However, the go-critic's `deprecatedComment` checker is not detecting this issue, which prevents users from identifying old code that will be removed in the near future and preparing to make necessary changes. Therefore, I would like to request that you implement this check as well.

### Additional contract requirements

When a `Deprecated:` notice is not in a separate paragraph, the checker reports the diagnostic message:

```
`Deprecated: ` notices should be in a dedicated paragraph, separated from the rest
```
