Footnote becomes H2
Happens if you have one and only one empty line after a footnote before a `---` divider:
```
julia> println(Franklin.fd2html("""
       hello[^a]

       [^a]: world

       ---
       """))
<p>hello<sup id="fnref:a"><a href="#fndef:a" class="fnref">[1]</a></sup>
<h2><table class="fndef" id="fndef:a">
    <tr>
        <td class="fndef-backref"><a href="#fnref:a">[1]</a></td>
        <td class="fndef-content">world</td>
    </tr>
</table>
</h2>
```

### Additional contract requirements

- For this input, the corrected HTML must be:
```html
<p>hello<sup id="fnref:a"><a href="#fndef:a" class="fnref">[1]</a></sup>
<table class="fndef" id="fndef:a">
    <tr>
        <td class="fndef-backref"><a href="#fnref:a">[1]</a></td>
        <td class="fndef-content">world</td>
    </tr>
</table>
<hr /></p>
```
