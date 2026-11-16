metaExpr introduces a local scope
```r
> exists("foo")
[1] FALSE
> shinymeta::metaExpr({foo <- TRUE})
[1] TRUE
> exists("foo")
[1] FALSE
```

I think this is due to the use of `rlang::eval_tidy`:

```r
> rlang::eval_tidy(quote(foo <- TRUE))
[1] TRUE
> exists("foo")
[1] FALSE
```

[HIDDEN]
