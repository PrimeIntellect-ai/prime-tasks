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

- For the input above, the rendered HTML must be:
```
<p>hello<sup id="fnref:a"><a href="#fndef:a" class="fnref">[1]</a></sup>
<table class="fndef" id="fndef:a">
    <tr>
        <td class="fndef-backref"><a href="#fnref:a">[1]</a></td>
        <td class="fndef-content">world</td>
    </tr>
</table>
<hr /></p>
```
- For the input `A\n---*\n***_\n`, the rendered HTML must be exactly `<p>A –-* ***_</p>`.

- A dash underline directly following text without a blank line must continue to render as a setext heading (for example, `A\n---\n` renders as `<h2>A</h2>`).
