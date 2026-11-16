BUG `benchopt run` crashes when the value returned by compute and used in StoppingCriterion is zero
If the value returned by compute is zero, it crashes.

![value_zero](https://github.com/benchopt/benchopt/assets/32032118/ec319d0b-bc5a-403c-97d4-15399ed2bd19)
