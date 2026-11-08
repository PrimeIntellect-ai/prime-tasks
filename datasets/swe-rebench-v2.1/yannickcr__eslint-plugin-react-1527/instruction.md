jsx-no-comment-textnodes rejecting html-entity "&#x2F;&#x2F;"
The rule `jsx-no-comment-textnodes` is warning when using html-entities for slashes
(`//` -> `&#x2F;&#x2F;`)

Example:
```html
<pre>&#x2F;&#x2F; TODO: Put instructions about usage here</pre>
```
This should not warn, since it is not valid comment.
