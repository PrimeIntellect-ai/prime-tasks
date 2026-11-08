Exceptions being swallowed after import errors in included templates
As stated in topic #1127, there are still problems with exceptions not being thrown in certain cases. I found out that if some problem happens with import errors inside included templates, Nunjucks will fail to generate the required exceptions. For example, create a template **included.njk**:

```njk
{% import 'unknown.njk' as nothing %}
String is {{ str | whatever }}
```
and the following script:

```js
const path = 'C:/users/etc/thispath';
const nunjucks = require("nunjucks");
nunjucks.configure(path);
console.log(nunjucks.renderString("{% include 'included.njk' %}", { str: 'okay' }));
```
Nunjucks silently outputs a `null` string. Some notes:

- The exception is captured correctly if the contents of the njk file are directly used as the template.
- The exception is also captured if the line with `import` is removed from the njk file.

I hope this is clear. Thanks in advance!

### Additional contract requirements

- When an included template imports the missing template `doesnotexist`, the thrown exception message must contain `template not found: doesnotexist`.
