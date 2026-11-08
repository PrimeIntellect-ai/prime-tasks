Unable to apply attributes to the last column of tables.
Unable to apply attributes to the last column of tables, if there is an attribute in the last `<td>` it will apply it to the parent `<tr>`.

**Markdown-it versions:**

```
markdown-it@13.0.1
markdown-it-attrs@4.1.6
```

**Example input:**

```md
| title | title |
| :----: | :----: |
| text | text {.text-primary} |
| text {.text-primary} | text |
```

**Current output:**

```html
<table>
  <thead>
    <tr>
      <th style="text-align:center">title</th>
      <th style="text-align:center">title</th>
    </tr>
  </thead>
  <tbody>
    <tr class="text-primary">
      <td style="text-align:center">text</td>
      <td style="text-align:center">text</td>
    </tr>
    <tr>
      <td style="text-align:center" class="text-primary">text</td>
      <td style="text-align:center">text</td>
    </tr>
  </tbody>
</table>
```

**Expected output:**

```html
<table>
  <thead>
    <tr>
      <th style="text-align:center">title</th>
      <th style="text-align:center">title</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td style="text-align:center">text</td>
      <td style="text-align:center" class="text-primary">text</td>
    </tr>
    <tr>
      <td style="text-align:center" class="text-primary">text</td>
      <td style="text-align:center">text</td>
    </tr>
  </tbody>
</table>
```

**Diff:**

```diff
<table>
  <thead>
    <tr>
      <th style="text-align:center">title</th>
      <th style="text-align:center">title</th>
    </tr>
  </thead>
  <tbody>
-    <tr class="text-primary">
+    <tr>
      <td style="text-align:center">text</td>
-      <td style="text-align:center">text</td>
+      <td style="text-align:center" class="text-primary">text</td>
    </tr>
    <tr>
      <td style="text-align:center" class="text-primary">text</td>
      <td style="text-align:center">text</td>
    </tr>
  </tbody>
</table>
```
