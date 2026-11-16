Generate URL for inline extensions
If an extension is defined using the Extension keyword, the url is created by SUSHI.  But if the extension is defined inline, the URL is not created by SUSHI, and an error results. Workaround: set the URL if you have inline extensions.

### Additional contract requirements

- For an inline extension slice named `my-inline-extension`, the generated `.url` element must have `fixedUri` equal to `my-inline-extension`.
