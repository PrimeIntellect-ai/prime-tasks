Some elements turning into None in html output with md_in_html
```python
import markdown
md = markdown.Markdown(extensions=["markdown.extensions.md_in_html"])
test = """
<div class="output_area" markdown="1">
<table>
<thead><tr>
<th style="text-align:right"></th>
<th style="text-align:right">time</th>
<th style="text-align:right">amplitude</th>
</tr>
</thead>
<tbody>
<tr>
<td style="text-align:right">0</td>
<td style="text-align:right">0</td>
<td style="text-align:right">0</td>
</tr>
</tbody>
</table>
</div>
"""
print(md.convert(test))
```

Which gives me -

```html
<div class="output_area">
<table>
<thead>None<tr>
<th style="text-align:right">None</th>
<th style="text-align:right">time</th>
<th style="text-align:right">amplitude</th>
</tr>
</thead>
<tbody>
<tr>
<td style="text-align:right">0</td>
<td style="text-align:right">0</td>
<td style="text-align:right">0</td>
</tr>
</tbody>
</table>
</div>
```

Rather than

```html
<div class="output_area">
<table>
<thead><tr>
<th style="text-align:right"></th>
<th style="text-align:right">time</th>
<th style="text-align:right">amplitude</th>
</tr>
</thead>
<tbody>
<tr>
<td style="text-align:right">0</td>
<td style="text-align:right">0</td>
<td style="text-align:right">0</td>
</tr>
</tbody>
</table>
</div>
```

Which is what I'm expecting - note the extra `None` before the `<tr>` in `<thead>` and in the first header.
