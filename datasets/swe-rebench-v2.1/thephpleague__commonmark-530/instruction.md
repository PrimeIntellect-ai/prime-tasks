Footnote ID prefix and footnote ref ID prefix config options sometimes ignored
**Version(s) affected**: 1.5.x

**Description**
<!-- A clear and concise description of the problem. -->

The `footnote/ref_id_prefix` and `footnote/footnote_id_prefix` configuration options are only used to generate element `id` attributes, but are ignored for the `href` attributes corresponding to those IDs, breaking all footnote reference links and backlinks if either config option is customized.

The default values for these configuration options, `fnref:` and `fn:`, are hard-coded in 5 places:

https://github.com/thephpleague/commonmark/blob/d9fdf5f5ea370c988375e54c85a43b2668a048e6/src/Extension/Footnote/Event/GatherFootnotesListener.php#L52

https://github.com/thephpleague/commonmark/blob/d9fdf5f5ea370c988375e54c85a43b2668a048e6/src/Extension/Footnote/Event/GatherFootnotesListener.php#L95

https://github.com/thephpleague/commonmark/blob/d9fdf5f5ea370c988375e54c85a43b2668a048e6/src/Extension/Footnote/Event/AnonymousFootnotesListener.php#L46

https://github.com/thephpleague/commonmark/blob/d9fdf5f5ea370c988375e54c85a43b2668a048e6/src/Extension/Footnote/Parser/AnonymousFootnoteRefParser.php#L80

https://github.com/thephpleague/commonmark/blob/d9fdf5f5ea370c988375e54c85a43b2668a048e6/src/Extension/Footnote/Parser/FootnoteRefParser.php#L59

**How to reproduce**
<!-- Markdown and/or config needed to reproduce the problem. Don't forget to mention any extensions you might have enabled! -->

Config:

```php
    'footnote' => [
        'ref_id_prefix' => 'customfnref:',
        'footnote_id_prefix' => 'customfn:',
    ],
```

Markdown:

```md
Here[^note1]

[^note1]: There
```

Expected HTML:

```html
<p>Here<sup id="customfnref:note1"><a class="custom-ref" href="#customfn:note1" role="doc-noteref">1</a></sup></p>
<div class="custom-notes" role="doc-endnotes">
    <ol>
        <li class="custom-footnote" id="customfn:note1" role="doc-endnote">
            <p>There&nbsp;<a class="custom-backref" rev="footnote" href="#customfnref:note1" role="doc-backlink">↩</a></p>
        </li>
    </ol>
</div>
```

Actual HTML:

```html
<!-- Correct id, wrong href -->
<p>Here<sup id="customfnref:note1"><a class="custom-ref" href="#fn:note1" role="doc-noteref">1</a></sup></p>
<div class="custom-notes" role="doc-endnotes">
    <ol>
        <!-- Correct id -->
        <li class="custom-footnote" id="customfn:note1" role="doc-endnote">
            <!-- Wrong href -->
            <p>There&nbsp;<a class="custom-backref" rev="footnote" href="#fnref:note1" role="doc-backlink">↩</a></p>
        </li>
    </ol>
</div>
```

**Possible Solution**
<!--- Optional: only if you have suggestions on a fix/reason for the bug -->

[HIDDEN] I'm not sure how involved this would be since it looks to me like none of those classes currently have access to the config at all.

But also, since these attributes are completely hidden from end users and don't affect styling, it occurred to me that they don't necessarily need to be customizable? An easier solution would be to hard-code them everywhere and not allow them to be overriden at all.

Thoughts? Either way, I'll try to get a PR in to fix this in the next week or two!

### Additional contract requirements

- Anonymous footnotes (the inline syntax `^[text]`) must honour the configured prefixes exactly like explicit footnotes: the generated reference `href` must use `footnote/footnote_id_prefix` and the generated back-reference `href` must use `footnote/ref_id_prefix`.
- Each prefix option must work when customized independently of the other. Customizing only `footnote/ref_id_prefix` must change the reference/back-reference `href` values that use it while `footnote/footnote_id_prefix` keeps its default (`fn:`), and vice versa.
