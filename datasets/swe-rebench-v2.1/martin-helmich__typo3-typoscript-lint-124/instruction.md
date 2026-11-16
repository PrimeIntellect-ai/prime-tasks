"Common path prefix" with ">" operator
Hi everyone,

I just have a question about the "Common path prefix"-Sniff:
While linting the following TypoScript the linter only warns about line 5 & 6 (`bar.baz`) but not about 2 & 3 (`foo.baa`).

Is this behaivor intended? And if so, why?

foo.typoscript
```
lib {
    foo.baa.10 >
    foo.baa.20 >

    bar.baz.10 = TEXT
    bar.baz.20 = TEXT
}
```

linter output
```
/usr/bin/php vendor/bin/typoscript-lint
W                                                    [1 / 1, 100%]

Completed with 4 issues

CHECKSTYLE REPORT
=> test/foo.typoscript
   5 Common path prefix "bar" with assignment to "bar.baz.20" in line 6. Consider merging them into a nested assignment.
   5 Common path prefix "bar.baz" with assignment to "bar.baz.20" in line 6. Consider merging them into a nested assignment.
   6 Common path prefix "bar" with assignment to "bar.baz.10" in line 5. Consider merging them into a nested assignment.
   6 Common path prefix "bar.baz" with assignment to "bar.baz.10" in line 5. Consider merging them into a nested assignment.

SUMMARY
4 issues in total. (4 warnings)
```

KamiYang

### Additional contract requirements

- For `>` operations, common-path-prefix warnings must use these exact message forms: `Common path prefix "<prefix>" with operation to "<path>" in line <line>. Consider merging them into a nested statement.` for one operation..
- For assignment statements, common-path-prefix warnings must use these exact message forms: `Common path prefix "<prefix>" with operation to "<path>" in line <line>. Consider merging them into a nested statement.` for one referenced assignment, and `Common path prefix "<prefix>" with operations to "<path>" in line <line>, "<path>" in line <line>. Consider merging them into a nested statement.` for multiple referenced assignments.
- Nested-statement conflict warnings must use the exact message form: `Operation on value "<path>", altough nested statement for path "<prefix>" exists at line <line>.`
