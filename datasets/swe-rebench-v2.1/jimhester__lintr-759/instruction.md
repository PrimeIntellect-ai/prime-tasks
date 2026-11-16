incorrectly tagged lint "Use FALSE instead of the symbol F"
Since a couple of days, I have started to get a new lint in my CI checks (https://github.com/IndrajeetPatil/statsExpressions/commit/cc00f65c4c6640c51cea165f6a557f13c097db85#commitcomment-44804914).

But I think this is unintentional, since here `F` refers to `F`-statistic

```r
R/helpers_anova.R:134:34: style: Use FALSE instead of the symbol F.

​        statistic = ez_df$ANOVA$F[2],

                                ~^
```

### Additional contract requirements

- When `T` or `F` is used as an assignment target, emit respectively the exact messages `Don't use T as a variable name, as it can break code relying on T being TRUE.` and `Don't use F as a variable name, as it can break code relying on F being FALSE.`
