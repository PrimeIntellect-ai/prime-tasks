Handle semantic line breaks when converting markdown file to an HTML file
Thanks for the work on `mark,` this is an amazing tool! It works great for my needs except for one subtle detail.
I believe it's the "opposite" of another issue: https://github.com/kovetskiy/mark/issues/61

Having this markdown snippet which follows the [semantic line breaks](https://sembr.org/) guide:

```markdown
If you want to save the file,
you can click Save.
```

Will generate this HTML file (which I see by using the `--dry-run` flag):

```html
<p>If you want to save the file,
you can click Save.</p>
```

When this HTML gets rendered in Confluence, the line breaks within the `<p>` tag are respected resulting in awkward breaks:

![image](https://user-images.githubusercontent.com/59651540/125070575-110f1880-e0b0-11eb-82f6-eaf4b48a2b61.png)

I believe most Markdown renderers would ignore single line breaks, so wrapping the text around some length shouldn't affect the rendered outcome. However, I assume Confluence handles the text within the `<p>` tag in a particular way treating those "soft" line breaks as break lines.

Do you have any control over the HTML generation in the `mark` code to be able to handle it differently to not let Jira make those line breaks?

Many thanks.

### Additional contract requirements

Provide the `--strip-linebreaks` command-line option to render semantic soft line breaks between wrapped Markdown lines as whitespace, preventing Confluence from treating them as unwanted line breaks. Deliberate Markdown hard breaks must remain line breaks when this option is enabled.
