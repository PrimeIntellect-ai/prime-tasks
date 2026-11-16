Newlines in table content are not un-escaped
Per `datatables_with_new_lines.feature` in the gherkin testdata, with a table like:

```
    Given 3 lines of poetry on 5 lines
      |  \nraindrops--\nher last kiss\ngoodbye.\n  |
```

The `\n` characters should be parsed as actual newlines, to give cell content matching:

```
raindrops--
her last kiss
goodbye.

```

However, we currently return these as the raw content, e.g. with explicit `\` `n` characters, rather than newlines.

See #325
