Breaks on complex interpolations
Currently, this breaks on a complex interpolation:

``` JS
const background = 'background: red;';
const Button = styled.div`
  color: red;
  ${background}
`;
```

We represent this for stylelint like so:

``` CSS
.selector {
  color: red;
  $background
}
```

The problem is that, while stylelint ignores Sass variables, those cannot represent full strings, which means stylelint throws a "CssSyntaxError" on the above code eventhough it's not a syntax error at all. 😕

Any ideas what we could do here @davidtheclark?

(also related to #4)

### Additional contract requirements

- Add a public function `isLastLineWhitespaceOnly(text)` in module `src/utils/general.js`. It accepts a string `text` and returns `true` exactly when the final line of `text` contains only spaces or tabs (including when `text` is empty), and `false` otherwise.


- Processing the complex-interpolation example must produce no stylelint warnings.
