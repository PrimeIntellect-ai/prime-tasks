Python Markdown turns `</#rrggbb>` into HTML comment, even while in inline code
When you put `</#rrggbb>` as-is inside a inline code block will Python Markdown convert it into a HTML comment (`<!--#rrggbb-->`), which feels odd.

Is there a way to prevent this? Using HTML escape methods such as `&lt;/#rrggbb&gt;` will not work, as Python Markdown will then treat the content literally and show it as-is.
Additionally can and will this cause issues with inline-code highlighting used.

### Additional contract requirements

- In ordinary Markdown text, render `<!invalid>` as `<p>&lt;!invalid&gt;</p>` and `</#invalid>` as `<p>&lt;/#invalid&gt;</p>`.
