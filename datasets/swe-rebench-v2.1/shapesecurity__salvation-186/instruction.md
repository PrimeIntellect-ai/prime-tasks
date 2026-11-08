Warn on duplicate keyword-sources
Ex. `script-src 'unsafe-inline' 'unsafe-inline'`

### Additional contract requirements

- A source list must emit one warning for every duplicate keyword-source: a
  keyword-source that is equal (case-insensitively) to a keyword-source that
  already appeared earlier in the same source list. The first occurrence is
  kept; each later occurrence produces one warning.
- The warning message must be exactly:
  `Source list contains duplicate source expression "<source-expression>". All but the first instance will be ignored.`
  where `<source-expression>` is the canonical `show()` form of the duplicate
  keyword-source (for example `'unsafe-inline'`).
- The warning must carry the location of the duplicate source expression, so
  that `Notice.show()` renders it as `<line>:<column>: <message>`.
- Warnings are emitted in the order in which the duplicate occurrences appear
  in the source.
