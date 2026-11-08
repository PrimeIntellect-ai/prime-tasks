gm_auth_configure() failing to auth with custom app provided via htrr::oauth_app()
Right now, while attempting to run first auth using custom app setup (see code below), gm_auth_configure() returns error requesting either for _path_ or _key_ and _secret_ parameters.

Not 100% sure if this is an error or just inconsistency with function documetation which uses code like below as an example. However, with other gargle-based apps, similar code works like charm

Code:
```
google_app <- httr::oauth_app(
    "my_google_app",
    key = "",
    secret = ""
)

gmailr::gm_auth_configure(app = google_app)
```
Error returned:
```
Error: Must supply either `key` and `secret` or `path`
```

My sessionInfo():
```
R version 4.0.2 (2020-06-22)
Platform: x86_64-pc-linux-gnu (64-bit)
Running under: Debian GNU/Linux 10 (buster)

Matrix products: default
BLAS:   /usr/lib/x86_64-linux-gnu/openblas/libblas.so.3
LAPACK: /usr/lib/x86_64-linux-gnu/libopenblasp-r0.3.5.so

locale:
 [1] LC_CTYPE=C.UTF-8       LC_NUMERIC=C           LC_TIME=C.UTF-8        LC_COLLATE=C.UTF-8     LC_MONETARY=C.UTF-8
 [6] LC_MESSAGES=C.UTF-8    LC_PAPER=C.UTF-8       LC_NAME=C              LC_ADDRESS=C           LC_TELEPHONE=C
[11] LC_MEASUREMENT=C.UTF-8 LC_IDENTIFICATION=C

attached base packages:
[1] stats     graphics  grDevices utils     datasets  methods   base

other attached packages:
[1] gmailr_1.0.0.9000 RMariaDB_1.0.9

loaded via a namespace (and not attached):
 [1] Rcpp_1.0.5      packrat_0.5.0   R6_2.4.1        lifecycle_0.2.0 DBI_1.1.0       magrittr_1.5    httr_1.4.2      rlang_0.4.7
 [9] vctrs_0.3.4     tools_4.0.2     bit64_4.0.2     bit_4.0.4       hms_0.5.3       compiler_4.0.2  pkgconfig_2.0.3 base64enc_0.1-3
```
