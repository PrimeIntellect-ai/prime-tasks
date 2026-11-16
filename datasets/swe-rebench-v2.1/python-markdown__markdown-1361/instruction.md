Regression in unescaping backslash in TOC title
Now I found another issue similar to #1358 and I checked that its fix doesn't also fix this one.

Regression in 3.4 - c0f6e5a31ea8e7fe98910a0523144c2a96fa9bf1 is the first bad commit

Reproduction code:
```python
import markdown

md = markdown.Markdown(extensions=['toc'])
s = r'''
### hello \[foo]
'''
md.convert(s)
print(md.toc_tokens)
```

Output before vs after:
```python
[{'level': 3, 'id': 'hello-foo', 'name': 'hello [foo]', 'children': []}]
```
```python
[{'level': 3, 'id': 'hello-foo', 'name': 'hello \x0291\x03foo]', 'children': []}]
```
