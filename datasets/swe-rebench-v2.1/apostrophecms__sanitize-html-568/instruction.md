It is possible to add a disallowed closing tag with valid HTML as well as opening tag with invalid HTML markup.
I found several variants of the library's incorrect behavior. In the examples below, it is possible to add any html tag (closing tag with valid HTML as well as opening tag with invalid HTML) if any tag is allowed.

## Example 1:

```
const sanitizeHtml = require('sanitize-html');

const sanitizedString = sanitizeHtml('<b><div/', {
    allowedTags: ['b'],
});
```
## Expected behavior
> As a result of the execution I expect to see ```<b></b>``` or a empty line. However, I get ```<b></div>```.

## Example 2:

```
const sanitizeHtml = require('sanitize-html');
const HTMLParser = require('node-html-parser');

const sanitizedString = sanitizeHtml('<b><b<<div/', {
    allowedTags: ['b'],
});

console.log(sanitizedString) // <b></b<<div>

const unespectedDiv = HTMLParser.parse(sanitizedString).querySelector('div');

console.log(unespectedDiv);
```
## Expected behavior
> As a result of the execution I expect to see ```<b></b>``` or a empty line. However, I get ```<b></b<<div>```. The resulting string contains a substring ```<div>```, which is interpreted by some parsers as a valid html tag like node-html-parser (Browsers interpret it correctly).

### Additional contract requirements

- For each of the two inputs shown above, with `allowedTags: ['b']`, sanitization must return exactly `<b></b>`.
