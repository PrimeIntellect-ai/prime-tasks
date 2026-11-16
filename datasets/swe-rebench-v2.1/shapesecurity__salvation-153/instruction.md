support "'unsafe-dynamic'" keyword
https://w3c.github.io/webappsec-csp/#strict-dynamic-usage

### Additional contract requirements

- The keyword-source requested above is spelled exactly `'strict-dynamic'` (the title's `'unsafe-dynamic'` is a typo for the CSP3 `'strict-dynamic'` keyword-source; `'unsafe-dynamic'` is not a keyword-source): parsing and `Policy.show()` must preserve that spelling, and policy union and intersection must preserve it in their results. In a `script-src` list, when `'strict-dynamic'` occurs with a host-source or scheme-source expression, `'self'`, or `'unsafe-inline'`, emit a warning notice for each such other expression. The notice must be a warning and its message must be exactly: `The 'strict-dynamic' keyword-source makes host-source and scheme-source expressions, as well as the "'unsafe-inline'" and "'self' keyword-sources unnecessary in CSP3 and later.`
