Table cell min-width is ignored when another cell has overflowing text
Two tables here to compare, note the `min-width` css rule:

```html
<head>
<style>
table td { border: 1px solid black; }
table.key-val tr td:nth-child(1) { min-width: 13em; }
</style>
</head>

<body>
<table class="key-val">
    <tbody>
        <tr>
            <td>Normal Key 1</td>
            <td>Normal Value 1</td>
        </tr>
        <tr>
            <td>Normal Key 2</td>
           <td>Normal Value 2</td>
        </tr>
    </tbody>
</table>
<br>
<table class="key-val">
    <tbody>
        <tr>
            <td>Short value</td>
            <td>Works as expected</td>
        </tr>
        <tr>
            <td>Long Value</td>
            <td>Annoyingly breaks my table layout: Sed ut perspiciatis unde omnis iste natus error sit voluptatem
                accusantium doloremque laudantium, totam rem aperiam,
                eaque ipsa quae ab illo inventore veritatis et quasi architecto beatae vitae dicta sunt explicabo.
            </td>
        </tr>
    </tbody>
</table>
</body>
```

Firefox:
![image](https://user-images.githubusercontent.com/3399022/122417277-a9bae880-cf89-11eb-94af-2891db73300d.png)

Weasyprint:
![image](https://user-images.githubusercontent.com/3399022/122417643-ec7cc080-cf89-11eb-9a48-ee3bd5e748c7.png)

I have experimented with different width units as well as tried adjusting `overflow-wrap` with no effect on Weasyprint's result.

### Additional contract requirements

After layout, a table cell box exposes its used `min_width` and rendered `width` as numeric attributes:

- `TableCellBox.min_width` is the resolved CSS `min-width` of the cell. When the computed `min-width` is `auto`, its value is `0`.
- `TableCellBox.width` is the final rendered width of the cell.

Both values are non-negative numbers.


- In the supplied example, `TableCellBox.width` of the first cell in each table is exactly `208`.
