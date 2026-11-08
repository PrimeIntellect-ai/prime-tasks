minify breaks jquery -> replaces \0 with NUL (Ascii)
Download jquery.min.js from https://code.jquery.com/jquery-3.2.1.min.js

Run Babel Minify on it.

Look at the result File and search for Ascii NUL -> you will find some

### Additional contract requirements

- When a regular expression is constructed from a string that contains a NUL escape, the resulting regular expression must preserve the NUL escape (`\0`) and must not contain a raw ASCII NUL byte.
- When transforming `var x = new RegExp('\0');`, the output must be exactly `var x = /\0/;`.
