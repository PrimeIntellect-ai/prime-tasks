When CodeHilite is enabled, fenced_code includes the language class in list of general classes.
In new version 3.3, I found that there is a new language class in HTML code block

My code:

````
import markdown

s = '''
```c
```
'''

print(markdown.markdown(s, extensions=['extra', 'codehilite']))
````

output with `c` class:

```html
<div class="c codehilite"><pre><span></span><code>
</code></pre></div>
```

My version info:

```console
$ python3 --version
Python 3.8.5
$ python3 -m pip show markdown
pyName: Markdown
Version: 3.3
Summary: Python implementation of Markdown.
Home-page: https://Python-Markdown.github.io/
Author: Manfred Stienstra, Yuri takhteyev and Waylan limberg
Author-email: waylan.limberg@icloud.com
License: BSD License
Location: /usr/local/lib/python3.8/dist-packages
Requires:
Required-by: pymdown-extensions, mkdocs, mkdocs-material, markdown-link-attr-modifier
```

According to this page [https://pygments.org/docs/lexers/](https://pygments.org/docs/lexers/), there are so many possibilities that the language class mess up with other class with the same name.

When pygments is disabled, there would be a `language-` prefix, which is acceptable. It would be better if we always add `language-` prefix, or just remove it.

Thank you!

### Additional contract requirements

- When CodeHilite is enabled, do not include the fenced language name in the outer element's class attribute. With Pygments enabled, a Python block's wrapper must be `<div class="codehilite">`; with Pygments disabled, it must be `<pre class="codehilite"><code class="language-python">`.
- For a fenced Python block with additional classes `foo` and `bar` in its attribute list, place those classes on `<pre>` while keeping the language class on `<code>`, as in `<pre class="foo bar"><code class="language-python">`.
