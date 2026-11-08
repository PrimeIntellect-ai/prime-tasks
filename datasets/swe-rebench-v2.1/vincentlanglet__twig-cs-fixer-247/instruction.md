Remove excess spacing before multiline block `%}`
### Rule(s) related to or rule(s) missing

Using the standard TwigCsFixer rules I notice something odd.

### Actual behavior

```twig
{% trans 'my.key' with {
    faqUrl: 'http://faq',
    contactUrl: 'http://contact',
    }

%}
```

### Expected behavior

```twig
{% trans 'my.key' with {
    faqUrl: 'http://faq',
    contactUrl: 'http://contact',
    } %}
```

Why isn't the excess newline and spacing not removed?

### Additional contract requirements

- `DelimiterSpacingRule` accepts an optional boolean constructor argument
  `skipIfNewLine` (default `true`). When it is `true`, a delimiter that is
  adjacent to a line break is left untouched, so the multiline example above is
  preserved unchanged. When it is `false`, the line break and the surrounding
  indentation next to the delimiter are collapsed into a single space, producing
  the `} %}` layout shown in the expected behavior above.
- `DelimiterSpacingRule::getConfiguration()` returns exactly
  `['skipIfNewLine' => <bool>]`, where `<bool>` is the configured value.
- Spacing rules (including `DelimiterSpacingRule`) report diagnostics in the form
  `Expecting <expected> whitespace after "<token>"; found <found>.` and
  `Expecting <expected> whitespace before "<token>"; found <found>.`, where
  `<found>` is the number of whitespace characters found, or the literal
  `newline` when the adjacent token is a line break. Each message ends with a
  period.
