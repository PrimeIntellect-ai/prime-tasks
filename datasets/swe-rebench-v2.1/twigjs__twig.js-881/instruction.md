The slice filter shorthand doesn't support variables
The slice filter type regex is `regex: /^\[(\d*:\d*)\]/,` which only matches something like `[10:]` but not `[length:]`. I can just use `|slice(length)` and `|slice(0, length)` but it's a little unexpected coming from php twig.
