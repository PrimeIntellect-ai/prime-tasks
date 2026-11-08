GFM tables without leading empty lines inside list items are interpreted incorrectly as plain text
Hello.

As title says, for example, if I run `cargo run - --enable-tables` with the following as input:
``` markdown
| A | table    |
| ------ | ---- |
| not   |  in  |
| a     | list|

* A blockquote:
  > inside a list item
* A Heading:
  # inside a list item
* A table:

  | inside | a       |
  | ------ | ------- |
  | list   | item    |
  | with   | leading |
  | empty  | lines   |
* A table:
  | inside  | a       |
  | ------- | ------- |
  | list    | item    |
  | without | leading |
  | empty   | lines   |
```

I'd expect the output to be [^1]:
> | A | table    |
> | ------ | ---- |
> | not   |  in  |
> | a     | list|
>
> * A blockquote:
>   > inside a list item
> * A Heading:
>   # inside a list item
> * A table:
>
>   | inside | a       |
>   | ------ | ------- |
>   | list   | item    |
>   | with   | leading |
>   | empty  | lines   |
> * A table:
>   | inside  | a       |
>   | ------- | ------- |
>   | list    | item    |
>   | without | leading |
>   | empty   | lines   |

But the actual output is:
> <!--begin--><table><thead><tr><th>A</th><th>table</th></tr></thead><tbody>
<tr><td>not</td><td>in</td></tr>
<tr><td>a</td><td>list</td></tr>
</tbody></table>
<ul>
<li>
<p>A blockquote:</p>
<blockquote>
<p>inside a list item</p>
</blockquote>
</li>
<li>
<p>A Heading:</p>
<h1>inside a list item</h1>
</li>
<li>
<p>A table:</p>
<table><thead><tr><th>inside</th><th>a</th></tr></thead><tbody>
<tr><td>list</td><td>item</td></tr>
<tr><td>with</td><td>leading</td></tr>
<tr><td>empty</td><td>lines</td></tr>
</tbody></table>
</li>
<li>
<p>A table:
| inside  | a       |
| ------- | ------- |
| list    | item    |
| without | leading |
| empty   | lines   |</p>
</li>
</ul><!--end--></blockquote>

<details><summary>Raw HTML of the actual output</summary>

``` html
<table><thead><tr><th>A</th><th>table</th></tr></thead><tbody>
<tr><td>not</td><td>in</td></tr>
<tr><td>a</td><td>list</td></tr>
</tbody></table>
<ul>
<li>
<p>A blockquote:</p>
<blockquote>
<p>inside a list item</p>
</blockquote>
</li>
<li>
<p>A Heading:</p>
<h1>inside a list item</h1>
</li>
<li>
<p>A table:</p>
<table><thead><tr><th>inside</th><th>a</th></tr></thead><tbody>
<tr><td>list</td><td>item</td></tr>
<tr><td>with</td><td>leading</td></tr>
<tr><td>empty</td><td>lines</td></tr>
</tbody></table>
</li>
<li>
<p>A table:
| inside  | a       |
| ------- | ------- |
| list    | item    |
| without | leading |
| empty   | lines   |</p>
</li>
</ul>
```
</details>

[^1]: I pasted the exact markdown text above to here and appended `> ` to the beginning of each line, so this is just how GitHub's markdown renderer renders my input.

---

As the above shows:
* Table extension is enabled (hence the first table above is rendered).
* Generally, block elements inside list items are rendered exactly as what they would be in other places, no matter if there are leading empty lines. The [CommonMark dingus](https://spec.commonmark.org/dingus/?text=*%20A%20blockquote%3A%0A%20%20%3E%20inside%20a%20list%20item%0A*%20A%20Heading%3A%0A%20%20%23%20inside%20a%20list%20item) also works this way (hence the blockquote and h1 above is rendered).
* However, unlike other block elements, `pulldown-cmark` interprets tables inside list items without leading empty lines as paragraphs, not tables.

Commit I built the binary from: 5088b21d09ef94b424c4d852db7648c9c94fb630 (The current head commit)
