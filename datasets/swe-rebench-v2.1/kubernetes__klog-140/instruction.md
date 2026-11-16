klogr flatten logs some strings oddly
/kind bug

**What steps did you take and what happened:**
Had a klogr log something with `>` in the string, and saw it come out as `u003e`

**What did you expect to happen:**
Just prints the `>` character


**Anything else you would like to add:**
https://play.golang.org/p/xoZ7_N1tkUw

### Additional contract requirements

- String values containing `<`, `&`, and `>` must print those characters literally; for example, `<&>` must appear as `"<&>"`, not as escaped Unicode sequences.
