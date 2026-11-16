New option: `jsx-one-expression-per-line` `non-jsx`
Examples of **incorrect** code for this rule:
```jsx
<Hello
  foo="bar
>Children
</Hello>
```
Examples of **correct** code for this rule:
```jsx
<Hello
  foo="bar
>
  Children
</Hello>
```

### Additional contract requirements

- The rule accepts an option object of the form `{ allow: 'non-jsx' }`: `allow` is the option key and `'non-jsx'` is one of its accepted string values.
- With `allow: 'non-jsx'`, a JSX element or fragment whose children consist only of text and/or expression containers is allowed to appear on a single line without a lint error, regardless of line breaks.

- With this option, direct JSX element or fragment children remain subject to the rule’s existing line-separation checks.
