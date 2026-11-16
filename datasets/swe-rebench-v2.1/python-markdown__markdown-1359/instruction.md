Regression in unescaping backslash in attribute
Regression in 3.4 - c0f6e5a31ea8e7fe98910a0523144c2a96fa9bf1 is the first bad commit

Reproduction code:
```python
import markdown

s = r'''
<img src="..\..\foo.png">
'''
print(repr(markdown.markdown(s)))
```

Output before vs after:
```python
'<p><img src="..\\..\\foo.png"></p>'
```
```python
'<p><img src="..\\\x0246\x03.\\foo.png"></p>'
```
