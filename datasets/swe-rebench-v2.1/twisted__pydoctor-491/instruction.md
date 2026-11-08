Colorize code inside ``..code ::`` directives
The code currently only displayed as a literal block, but no syntax highlight is applied.
I think we could re-use the doctest syntaxt highlight and apply it to the ``..code ::`` directive, too.

### Additional contract requirements

- The `.. code::` directive must accept the `:number-lines:` and `:linenos:` options without reporting errors, but ignore them: they must not appear in the rendered HTML or add line numbers.
