Extension Fenced Code Blocks breaks HTML formatting on quotes in attributes
The extension **fenced code blocks** (https://python-markdown.github.io/extensions/fenced_code_blocks/#attributes) breaks the HTML formatting when a language, id or class contains a quotation-mark (").

https://github.com/Python-Markdown/markdown/blob/master/markdown/extensions/fenced_code.py#L122-L127

The following snippet
````
``` { .">outside}

```
````
will render as
```
<pre><code class="language-">outside">
</code></pre>
```

Even though the users of **Python-Markdown** are responsible for sanitizing / escaping the end-result, this might lead to some unintended behaviour (as seen in https://github.com/netbox-community/netbox/issues/9292).

### Additional contract requirements

- With the `attr_list` extension enabled, the input
````
``` { ."weird #"foo bar=">baz }
# Some python code
```
````
must render exactly as:
```html
<pre id="&quot;foo"><code class="language-&quot;weird" bar="&quot;&gt;baz"># Some python code
</code></pre>
```
