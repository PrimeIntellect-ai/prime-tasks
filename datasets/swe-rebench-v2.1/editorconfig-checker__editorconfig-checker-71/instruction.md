Add flags to disable checks
- [x] Indentation
- [x] Final newline
- [x] Line ending
- [x] Trailing whitespace

### Additional contract requirements

The command line interface must register one boolean flag per check, named exactly:

- `-disable-indentation` disables the indentation check
- `-disable-final-newline` disables the final newline check
- `-disable-line-ending` disables the line ending check
- `-disable-trailing-whitespace` disables the trailing whitespace check

Passing one of these flags disables only the corresponding check. The command
exits with a non-zero status when it reports a violation, and exits with status
0 when every violation it would otherwise report is disabled by the matching
flag.
