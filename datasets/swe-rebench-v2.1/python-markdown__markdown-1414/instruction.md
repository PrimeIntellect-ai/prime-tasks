attr_list breaks if the value contains braces, requires HTML-encoding them
This issue originated from squidfunk/mkdocs-material#6177 where I was exploring the "override copied text" feature.

The following code block breaks Markdown parsing:

````markdown
``` { .c data-copy="int main() { return 0; }" }
Try copying me for some C code
```
````

It doesn't quite make sense to me as everything is already inside double quotes.

Instead, HTML-encoding the braces (and you can add newlines) solves the problem:

````markdown
``` { .c data-copy="int main() &#123;&#10;  return 0;&#10;&#125" }
Try copying me for some C code
```
````

Using HTML-encoding is not intuitive to most users. Maybe this could get changed to Python escapes?

### Additional contract requirements

- Also preserve the existing rendering of these extra-closing-brace cases. `# Heading {.a} }` must render as `<h1>Heading {.a} }</h1>`. The fenced input below must render exactly as shown.

````markdown
``` { data-test="{}" } }
# Some python code
```
```
test
```
````

````html
<p>``` { data-test="{}" } }</p>
<h1>Some python code</h1>
<pre><code></code></pre>
<p>test
```</p>
````
- Also preserve these existing renderings:

- `*inline*{data-test="x" =a} *text*` must render as `<p><em data-test="x">inline</em> <em>text</em></p>`.
- `# Heading {foo="bar}` must render as `<h1 foo="&quot;bar">Heading</h1>`.
