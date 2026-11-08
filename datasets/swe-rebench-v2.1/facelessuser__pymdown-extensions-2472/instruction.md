SuperFences produces different/"invalid" HTML after 10.11
### Description

SuperFences started producing "invalid" HTML after 10.11.
It happens for code blocks without language that use `hl_lines`, e.g.:
````
``` hl_lines="1"
some
code
```
````

I am aware that it got changed in that version but it breaks the code that is working fine in 10.10.2.

### Minimal Reproduction

1. use the following python code
```python
import markdown
text = ('``` hl_lines="1"\n'
        "test\n"
        "data\n"
        "```\n"
        "\n"
        "some text\n"
        "```sql\n"
        "select * from dual;\n"
        "```")
html = markdown.markdown(text, extensions=['pymdownx.superfences'])
print(html)
```

2. run in 10.10.2:
```html
<pre class="highlight"><code>test
data</code></pre>
<p>some text
<pre class="highlight"><code class="language-sql">select * from dual;</code></pre></p>
```

3. run in 10.11:
```html
<p>``` hl_lines="1"
test
data
<pre class="highlight"><code>
some text
```sql
select * from dual;</code></pre></p>
```

### Version(s) & System Info

- Operating System: Windows 10
- Python Version: 3.12
- Package Version: `pymdown-extensions-10.11`
