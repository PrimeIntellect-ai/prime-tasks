`font-variant="small-caps"` not supported for `<name>`
Hi folks,

I want to make a minor adjustment to the IEEE CSL definition, basically just having all author names in small caps. However, if I use small-caps as the `@font-variant` of the `<name>` element itself, Typst does not render it correctly, it gets ignored.
When I move it up in the hierarchy to `<names>` it works, but will also show non-name words like "and" in small caps which I don't want.

Here is a screenshot showing that small-caps is ignored (see line 115):
![image](https://github.com/typst/hayagriva/assets/8217108/1d8df618-cd95-4c9f-bed0-cfdb72bcf23a)

### Additional contract requirements

The formatting attributes specified on the `<name>` element are inherited by the individual name parts (given name and family name) that are rendered for that name. Concretely, when the citeproc test renderer emits the name parts, the inherited formatting is rendered as:

- `font-weight="bold"` wraps the name parts in `<b>...</b>`;
- `font-style="italic"` wraps them in `<i>...</i>`;
- `font-variant="small-caps"` wraps them in `<span style="font-variant:small-caps;">...</span>`;
- `text-decoration="underline"` wraps them in `<u>...</u>`;
- `vertical-align="sup"` wraps them in `<sup>...</sup>`.

Formatting specified on a `<name-part>` element is applied on top of the formatting inherited from the enclosing `<name>` element.
