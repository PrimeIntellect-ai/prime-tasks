URIError: malformed URI sequence
When you reload a page with a URL having the form '?q=%'  an error occurs **URIError: malformed URI sequence**

Solution:

`        [HIDDEN]
            val = val === undefined ? null : [HIDDEN];
        } [HIDDEN]`

Is it correct?

### Additional contract requirements

- Parsing a query string with a parameter value containing malformed percent-encoding, such as `?q=%`, must not throw a `URIError` and must return a parsed result containing that parameter.
