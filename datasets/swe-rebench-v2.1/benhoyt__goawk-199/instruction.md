Add support for --csv (which Gawk and onetrueawk are adding)
Gawk and BWK's onetrueawk are adding a `--csv` option (for the second edition of *The AWK Programming Language*), which I believe is equivalent to GoAWK's `-i csv`. We should confirm that and then add support for this argument to GoAWK for compatibility. Arnold said:

> In particular:
>        - Quoted fields are handled
>                - Including embedded CR-LF or CR or LF
>        - The record can be terminated by CR-LF or just LF
>        - In all cases, CR-LF becomes just LF by the time gawk sees the data

### Additional contract requirements

- The `-csv` spelling must also be accepted as equivalent to `-i csv`.
