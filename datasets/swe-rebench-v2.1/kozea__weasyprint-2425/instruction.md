list-style-position: outside yields incorrect result
I'm tyring to render ordered and unordered lists according to an existing style. This involes a lot of padding between the list element marker and the list element text.

The following demonstrates what I'm seeing:

```python
import weasyprint
css='''
ul {
    border: red;
    border-style: solid;
    margin-left: 0;
    padding-left: 0;
}

ul.outside {
    list-style-position: outside;
}

ul.inside {
    list-style-position: inside;
}

li {
    border: green;
    border-style: solid;
    margin-left: 1em;
    padding-left: 5em;
}

'''

html='''
<HTML>
<HEAD>
<TITLE>List style test</TITLE>
<link rel="stylesheet" href="test.css">
</HEAD>
<BODY>
<UL class="outside">
<LI> list-style-position: outside </LI>
<LI> list-style-position: outside </LI>
<LI> list-style-position: outside </LI>
<LI> list-style-position: outside </LI>
</UL>
<UL class="inside">
<LI> list-style-position: inside </LI>
<LI> list-style-position: inside </LI>
<LI> list-style-position: inside </LI>
<LI> list-style-position: inside </LI>
</UL>
</BODY>
</HTML>
'''

with open('test.css', 'w') as cssfile:
    cssfile.write(css)

with open('test.html', 'w') as htmlfile:
    htmlfile.write(html)

weasyprint.HTML(string=html).write_pdf('test.pdf', stylesheets=[weasyprint.CSS(string=css)])

```
Compare `test.html` with `test.pdf`

The UL has a green border and LI red for indication of the box locations only. The list element padding is large to show the problem clearly.

In HTML this is rendered as:

![image](https://user-images.githubusercontent.com/15229879/151821882-ba3d3a2f-6dc9-4938-bf4c-e8efd0b6bcf3.png)

In the PDF:

![image](https://user-images.githubusercontent.com/15229879/151822240-2f199994-eeaa-4277-b30f-81547c605e10.png)

I'm no web designer/PDF typsetter by trade but it seems like the bullet it's placed outside the contining box for the LI in WeasyPrint but just offset by some fixed amount. Or am I completely wrong?

### Additional contract requirements

- For `list-style-position: outside`, the marker's horizontal position must be exactly one marker width to the left of the list item's horizontal position.
