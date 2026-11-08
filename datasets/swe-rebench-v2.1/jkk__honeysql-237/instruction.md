HoneySQL converts SQL keywords to uppercase using system Locale
`String.toUpperCase()` or `string/upper-case` for that matter converts the string to uppercase for the default system locale (system property `user.language`). Normally this still does what you'd expect but things like `inner join` get converted to `İNNER JOIN` (dot over the I) when user locale is Turkish. This predictably has bad consequences for people who like their SQL queries to work. [HIDDEN]

I will submit a PR in a few minutes.

### Additional contract requirements

- SQL keyword uppercasing must be independent of the system default locale. For example, formatting `inner join` under a Turkish locale must produce `INNER JOIN`, not `İNNER JOIN`.
