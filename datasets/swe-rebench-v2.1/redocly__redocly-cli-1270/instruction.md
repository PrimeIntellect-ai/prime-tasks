no-server-example.com
**Describe the bug**

https://github.com/Redocly/redocly-cli/blob/main/packages/core/src/rules/oas3/no-server-example.com.ts#L6

This only detects an exact match `localhost` or `example.com` but the intention is for it to match https://example.com and http://foo.example.com too (etc...).

**To Reproduce**


**Expected behavior**

Match: https://example.com and https://foo.example.com.

Perhaps we can change it to this:
```js
[HIDDEN]
```


<!-- A clear and concise description of what you expected to happen. -->

**Logs**

n/a

**OpenAPI description**

n/a


**Redocly Version(s)**

Latest (1.2)

**`Node.js` Version(s)**

18

**Additional context**

<!-- Add any other context about the problem here. -->

### Additional contract requirements

- Report server URLs for example.com and its subdomains, including `https://example.com` and `http://foo.example.com`.
- Continue reporting the exact server URL `localhost`.
- When the rule reports a server URL, its message must be exactly: "Server `url` should not point to example.com or localhost."
