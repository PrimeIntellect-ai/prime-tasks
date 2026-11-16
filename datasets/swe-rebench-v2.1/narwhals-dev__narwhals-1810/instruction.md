test: check if we have a test for `nw.when(nw.col('a')>1).then(nw.lit(0)).otherwise(nw.lit(1))`
Do we have a case where both are literals?

It would be good to investigate this, and add a test if necessary
