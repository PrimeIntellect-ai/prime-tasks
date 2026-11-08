katex.render double encodes HTML entities in MathML
`katex.render` double encodes HTML entities in MathML. For example, the following formula:

```latex
x < y
```

Produces an element with the following MathML:

```html
<math>
  <semantics>
    <mrow><mi>x</mi><mo>&amp;lt;</mo><msup><mi>y</mi><mn>2</mn></msup></mrow>
    <annotation encoding=\"application/x-tex\">x &amp;lt; y^2</annotation>
  </semantics>
</math>
```

`&amp;lt;` is produced, `&lt;` is expected.

`katex.renderToString` is not affected by the issue (`element.innerHTML = katex.renderToString` produces expected output).
