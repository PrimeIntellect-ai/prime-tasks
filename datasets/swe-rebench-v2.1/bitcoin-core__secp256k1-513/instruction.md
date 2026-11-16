Increase sparsity of pippenger fixed window naf representation
The current fixed window naf used in the pippenger never produces zeros in its representation, even though the code handles them fine and they're faster.   The existing representation can be converted into one where there are more zeros [HIDDEN]

For small windows (where pippenger is already slower than strauss) it's a pretty big speedup.  For realistic window sizes it probably isn't a big speedup, but free performance is good.

### Additional contract requirements

- In the Pippenger fixed-window NAF, a coefficient of 1 must be represented as zero when the immediately lower-position coefficient is negative, and a coefficient of -1 must be represented as zero when the immediately lower-position coefficient is positive. The resulting digits, together with the returned skew, must still represent the same scalar.

- For window size 4 and scalar `0x01ef1ef1`, the fixed-window NAF coefficients `wnaf[0]` through `wnaf[7]` must be exactly `{-0xf, 0, 0xf, -0xf, 0, 0xf, 1, 0}`, and the returned skew must be `0`.
