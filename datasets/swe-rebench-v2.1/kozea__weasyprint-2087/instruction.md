Table not printed as shown in browser: weasyprint overrides "table width" with "cell width"
If the table (table) has a maximum width and the individual columns (td) have their own width - greater than the table width(!) - weasyprint interprets the width different as browsers will do:

A Table with "table width 500px" and "td width 3000px" will shown as follows:

- Browsers take the table-width as the relevant width -> Table will be 500px wide
- Weasyprint takes the td-width as relevant width -> Table will be 3000px wide (table will be cut off!)

![table-bug](https://github.com/Kozea/WeasyPrint/assets/5119643/1b2040bf-02ea-4a09-937d-6adc3a4601f9)

### Example code

```html
<!DOCTYPE html><html class="view  chrome"  lang="de">
<p> Table Width: 500px </p>
<div>
<div style="overflow:auto">
<div class="text-content">
<table border="1" cellpadding="1" cellspacing="1" style="width:500px">
<tbody>
<tr>
<td style="width:3000px">Width: 3000px</td>
<td style="width:609px">2</td>
</tr>
<tr>
<td style="width:927px">Width: 927px</td>
<td style="width:609px">2</td>
</tr>
<tr>
<td style="width:927px">Width: 927px</td>
<td style="width:609px">2</td>
</tr>
</tbody>
</table><p>&nbsp;</p>
</div>
</div>
</div>
</html>
```
