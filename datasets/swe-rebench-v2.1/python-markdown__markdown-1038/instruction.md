Unclosed script and style tags cause data loss
Markdown 3.3 does not properly generate HTML for `` `<script>` ``
markdown:

Current output:
```python
Python 3.8.6 (default, Sep 30 2020, 04:00:38)

In [1]: import markdown

In [2]: markdown.__version__
Out[2]: '3.3'

In [3]: markdown.markdown('test: `test`')
Out[3]: '<p>test: <code>test</code></p>'

In [4]: markdown.markdown('test: `<script>`')
Out[4]: '<p>test: `<script></p>'
```

Expected output:
```python
In [1]: import markdown

In [2]: markdown.__version__
Out[2]: '3.2.2'

In [3]: markdown.markdown('test: `test`')
Out[3]: '<p>test: <code>test</code></p>'

In [4]: markdown.markdown('test: `<script>`')
Out[4]: '<p>test: <code>&lt;script&gt;</code></p>'
```
